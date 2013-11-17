#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define DISPATCH tag >> 5 ? dispatch_shift[tag >> 5](aTHX) : dispatch[tag](aTHX)

// TODO non fixed cache size?
uint8_t *cache_keys[100], cache_pos, *in, *out, tag;
uint32_t cache_sizes[100];

SV* read_undef(pTHX);
SV* read_bool_true(pTHX);
SV* read_bool_false(pTHX);
SV* read_byte(pTHX);
SV* read_short(pTHX);
SV* read_double(pTHX);
SV* read_int(pTHX);
SV* read_long(pTHX);
SV* read_float(pTHX);
SV* read_date(pTHX);
SV* read_map(pTHX);
SV* read_solr_doc(pTHX);
SV* read_solr_doc_list(pTHX);
SV* read_byte_array(pTHX);
SV* read_iterator(pTHX);
SV* read_string(pTHX);
SV* read_small_int(pTHX);
SV* read_small_long(pTHX);
SV* read_array(pTHX);

SV *(*dispatch[15])(pTHX) = {
    read_undef,
    read_bool_true,
    read_bool_false,
    read_byte,
    read_short,
    read_double,
    read_int,
    read_long,
    read_float,
    read_date,
    read_map,
    read_solr_doc,
    read_solr_doc_list,
    read_byte_array,
    read_iterator,
};

/* These datatypes are matched by taking the tag byte, shifting it by 5 so to only read
   the first 3 bits of the tag byte, giving it a range or 0-7 inclusive.

   The remaining 5 bits can then be used to store the size of the datatype, e.g. how
   many chars in a string, this therefore has a range of 0-31, if the size exceeds or
   matches this then an additional vint is added.

   The overview of the tag byte is therefore TTTSSSSS with T and S being type and size. */
SV *(*dispatch_shift[7])(pTHX) = {
    NULL,
    read_string,
    read_small_int,
    read_small_long,
    read_array,
    read_map,
    read_map,
};

// Lucene variable-length +ve integer, the MSB indicates whether you need another octet.
// http://lucene.apache.org/core/old_versioned_docs/versions/3_5_0/fileformats.html#VInt
uint32_t variable_int(void) {
    uint8_t shift;
    uint32_t result = (tag = *(in++)) & 127;

    for (shift = 7; tag & 128; shift += 7)
        result |= ((uint32_t)((tag = *(in++)) & 127)) << shift;

    return result;
}

uint32_t read_size(void) {
    uint32_t size = tag & 31;

    if ( size == 31 )
        size += variable_int();

    return size;
}

SV* read_undef(pTHX) { return &PL_sv_undef; }

SV* read_bool_true(pTHX) {
    return Perl_sv_bless(
        aTHX_
        Perl_newRV_noinc(aTHX_ Perl_newSVuv(aTHX_ 1)),
        Perl_gv_stashpv(aTHX_ "JavaBin::Bool", GV_ADD)
    );
}

SV* read_bool_false(pTHX) {
    return Perl_sv_bless(
        aTHX_
        Perl_newRV_noinc(aTHX_ Perl_newSVuv(aTHX_ 0)),
        Perl_gv_stashpv(aTHX_ "JavaBin::Bool", GV_ADD)
    );
}

SV* read_byte(pTHX) { return Perl_newSViv(aTHX_ (int8_t) *(in++)); }

SV* read_short(pTHX) {
    int16_t s = (int16_t) ((in[0] << 8) | in[1]);

    in += 2;

    return Perl_newSViv(aTHX_ s);
}

// For perls with double length NVs this conversion is simple.
// Read 8 bytes, cast to double, return. For long double perls
// more magic is used, see read_float for more details.
SV* read_double(pTHX) {
    uint64_t i = ((uint64_t) in[0] << 56) |
                 ((uint64_t) in[1] << 48) |
                 ((uint64_t) in[2] << 40) |
                 ((uint64_t) in[3] << 32) |
                 ((uint64_t) in[4] << 24) |
                 ((uint64_t) in[5] << 16) |
                 ((uint64_t) in[6] << 8 ) |
                 ((uint64_t) in[7]);

    in += 8;

#ifdef USE_LONG_DOUBLE
    char *str;

    asprintf(&str, "%.14f", *(double*)&i);

    long double d = strtold(str, NULL);

    free(str);

    return Perl_newSVnv(aTHX_ d);
#else
    return Perl_newSVnv(aTHX_ *(double*)&i);
#endif
}

SV* read_int(pTHX) {
    int32_t i = (int32_t) ((in[0] << 24) | (in[1] << 16) | (in[2] << 8) | in[3]);

    in += 4;

    return Perl_newSViv(aTHX_ i);
}

SV* read_long(pTHX) {
    int64_t l = ((uint64_t) in[0] << 56) |
                ((uint64_t) in[1] << 48) |
                ((uint64_t) in[2] << 40) |
                ((uint64_t) in[3] << 32) |
                ((uint64_t) in[4] << 24) |
                ((uint64_t) in[5] << 16) |
                ((uint64_t) in[6] << 8 ) |
                ((uint64_t) in[7]);

    in += 8;

    return Perl_newSViv(aTHX_ l);
}

// JavaBin has a 4byte float format, NVs in perl are either double or long double,
// therefore a little magic is required. Read the 4 bytes into an int in the
// correct endian order. Re-read these bits as a float, stringify this float,
// then finally numify the string into a double or long double.
SV* read_float(pTHX) {
    uint32_t i = ((in[0] << 24) | (in[1] << 16) | (in[2] << 8) | in[3]);

    in += 4;

    char *str;

    asprintf(&str, "%f", *(float*)&i);

#ifdef USE_LONG_DOUBLE
    long double d = strtold(str, NULL);
#else
    double d = strtod(str, NULL);
#endif

    free(str);

    return Perl_newSVnv(aTHX_ d);
}

SV* read_date(pTHX) {
    int64_t date_ms = ((uint64_t) in[0] << 56) |
                      ((uint64_t) in[1] << 48) |
                      ((uint64_t) in[2] << 40) |
                      ((uint64_t) in[3] << 32) |
                      ((uint64_t) in[4] << 24) |
                      ((uint64_t) in[5] << 16) |
                      ((uint64_t) in[6] << 8 ) |
                      ((uint64_t) in[7]);

    in += 8;

    time_t date = date_ms / 1000;

    struct tm *t = gmtime(&date);

    char date_str[25];

    sprintf(date_str, "%u-%02u-%02uT%02u:%02u:%02u.%03uZ", t->tm_year + 1900,
                                                           t->tm_mon + 1,
                                                           t->tm_mday,
                                                           t->tm_hour,
                                                           t->tm_min,
                                                           t->tm_sec,
                                                           (uint32_t) (date_ms % 1000));

    return Perl_newSVpvn(aTHX_ date_str, 24);
}

SV* read_map(pTHX) {
    HV *hv = newHV();

    uint32_t i, key_size, size = tag >> 5 ? read_size() : variable_int();

    for (i = 0; i < size; i++) {
        uint8_t *key;

        tag = *(in++);

        if ((key_size = read_size())) {
            key = cache_keys[key_size];

            key_size = cache_sizes[key_size];
        }
        else {
            tag = *(in++);

            cache_sizes[++cache_pos] = key_size = read_size();

            cache_keys[cache_pos] = key = in;

            in += key_size;
        }

        tag = *(in++);

        Perl_hv_common(aTHX_ hv, NULL, (char *)key, key_size, 0, HV_FETCH_ISSTORE, DISPATCH, 0);
    }

    return Perl_newRV_noinc(aTHX_ (SV*) hv);
}

SV* read_solr_doc(pTHX) {
    tag = *(in++);

    // Assume the doc is implemented as a simple ordered map.
    return read_map(aTHX);
}

SV* read_solr_doc_list(pTHX) {
    HV *hv = newHV();

    // Assume values are in an array, skip tag & DISPATCH.
    in++;

    // Assume numFound is a small long.
    tag = *(in++);
    Perl_hv_common(aTHX_ hv, NULL, STR_WITH_LEN("numFound"), 0, HV_FETCH_ISSTORE, read_small_long(aTHX), 0);

    // Assume start is a small long.
    tag = *(in++);
    Perl_hv_common(aTHX_ hv, NULL, STR_WITH_LEN("start"), 0, HV_FETCH_ISSTORE, read_small_long(aTHX), 0);

    // Assume maxScore is either a float or undef.
    tag = *(in++);
    Perl_hv_common(aTHX_ hv, NULL, STR_WITH_LEN("maxScore"), 0, HV_FETCH_ISSTORE, tag ? read_float(aTHX) : &PL_sv_undef, 0);

    // Assume docs are an array.
    tag = *(in++);
    Perl_hv_common(aTHX_ hv, NULL, STR_WITH_LEN("docs"), 0, HV_FETCH_ISSTORE, read_array(aTHX), 0);

    return Perl_newRV_noinc(aTHX_ (SV*) hv);
}

SV* read_byte_array(pTHX) {
    AV *av = newAV();
    uint32_t i, size = variable_int();

    for ( i = 0; i < size; i++ )
        av_store(av, i, newSViv((int8_t) *(in++)));

    return Perl_newRV_noinc(aTHX_ (SV*) av);
}

SV* read_iterator(pTHX) {
    AV *av = newAV();
    uint32_t i = 0;

    while ((tag = *(in++)) != 15)
        av_store(av, i++, DISPATCH);

    return Perl_newRV_noinc(aTHX_ (SV*) av);
}

SV* read_string(pTHX) {
    uint32_t size = read_size();

    SV *string = Perl_newSVpvn_flags(aTHX_ (char *)in, size, SVf_UTF8);

    in += size;

    return string;
}

SV* read_small_int(pTHX) {
    uint32_t result = tag & 15;

    if (tag & 16)
        result |= variable_int() << 4;

    return Perl_newSVuv(aTHX_ result);
}

SV* read_small_long(pTHX) {
    uint64_t result = tag & 15;

    // Inlined variable-length +ve long code, see variable_int().
    if (tag & 16) {
        uint8_t shift = 4;

        do result |= ((uint64_t)((tag = *(in++)) & 127)) << shift;
        while (tag & 128 && (shift += 7));
    }

    return Perl_newSVuv(aTHX_ result);
}

SV* read_array(pTHX) {
    AV *av = newAV();

    uint32_t i, size = read_size();

    for (i = 0; i < size; i++) {
        tag = *(in++);

        Perl_av_store(aTHX_ av, i, DISPATCH);
    }

    return Perl_newRV_noinc(aTHX_ (SV*) av);
}

void write_v_int(uint32_t i) {
    // FIXME
    while ((i & ~0x7F) != 0) {
        *(out++) = (uint8_t) ((i & 0x7f) | 0x80);

        //i >>>= 7;
    }

    *(out++) = (uint8_t) i;
}

void write_shifted_tag(uint8_t tag, uint32_t len) {
    if (len < 31)
        *(out++) = tag | len;
    else {
        *(out++) = tag | 31;

        write_v_int(len - 31);
    }
}

void write_sv(pTHX_ SV *sv) {
    bool ref = FALSE;

    if (SvROK(sv)) {
        ref = TRUE;
        sv = SvRV(sv);
    }

    switch (SvTYPE(sv)) {
        case SVt_NULL:
            *(out++) = 0;
            break;
        case SVt_IV: {
            int64_t i = SvIV(sv);
            fprintf(stderr, "%ld\n", i);
            break;
        }
        case SVt_PV:
            if (ref)
                Perl_croak("Invalid to_javabin input: string ref");

            STRLEN len = SvCUR(sv);

            write_shifted_tag(32, len);

            memcpy(out, SvPVX(sv), len);

            out += len;

            break;
        case SVt_REGEXP:
            Perl_croak("Invalid to_javabin input: regex");
        case SVt_PVGV:
            Perl_croak("Invalid to_javabin input: glob");
        case SVt_PVAV:
            fprintf(stderr, "arrayref\n");
            break;
        case SVt_PVHV:
            fprintf(stderr, "hashref\n");
            break;
        case SVt_PVCV:
            Perl_croak("Invalid to_javabin input: sub ref");
        default:
            fprintf(stderr, "other: %d\n", SvTYPE(sv));
    }
}

MODULE = JavaBin PACKAGE = JavaBin
VERSIONCHECK: DISABLE

void true()
PPCODE:
    ST(0) = Perl_sv_2mortal(aTHX_ read_bool_true(aTHX));

    XSRETURN(1);

void false()
PPCODE:
    ST(0) = Perl_sv_2mortal(aTHX_ read_bool_false(aTHX));

    XSRETURN(1);

void from_javabin(...)
PPCODE:
    if (!items) return;

    // Zero the cache.
    // TODO zero more than just the cache index?
    cache_pos = 0;

    if ( SvCUR(ST(0)) < 2 )
        Perl_croak("Invalid from_javabin input: insufficient length");

    in = (uint8_t *) SvPVX(ST(0));

    if ( *(in++) != 2 )
        Perl_croak("Invalid from_javabin input: expected version 2");

    tag = *(in++);

    ST(0) = Perl_sv_2mortal(aTHX_ DISPATCH);

    XSRETURN(1);

void to_javabin(...)
PPCODE:
    if (!items) return;

    //FIXME obviously
    uint8_t *out_start = out = malloc(1000);

    *(out++) = '\2';

    write_sv(aTHX_ ST(0));

    ST(0) = Perl_newSVpvn_flags(aTHX_ (char *)out_start, out - out_start, 0);

    free(out_start);

    XSRETURN(1);

MODULE = JavaBin PACKAGE = JavaBin::Bool
PROTOTYPES: DISABLE
FALLBACK: TRUE

void overload(...)
OVERLOAD: 0+ \"\"
PPCODE:
    ST(0) = SvRV(ST(0));

    XSRETURN(1);
