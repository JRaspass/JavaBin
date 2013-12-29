#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define DISPATCH tag >> 5 ? dispatch_shift[tag >> 5](aTHX) : dispatch[tag](aTHX)

typedef union { uint64_t i; double d; } int_to_double;
typedef union { uint32_t i; float  f; } int_to_float;

// TODO non fixed cache size?
uint8_t *cache_keys[100], cache_pos, *in, *out, tag;
uint32_t cache_sizes[100];

// Computed at boot hash keys.
uint32_t docs, maxScore, numFound, start;

// Globally stored JavaBin::Bool's of true and false.
SV *bool_true, *bool_false;

SV* read_undef(pTHX);
SV* read_true(pTHX);
SV* read_false(pTHX);
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
SV* read_enum(pTHX);
SV* read_string(pTHX);
SV* read_small_int(pTHX);
SV* read_small_long(pTHX);
SV* read_array(pTHX);

SV *(*dispatch[19])(pTHX) = {
    read_undef,
    read_true,
    read_false,
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
    NULL,
    NULL,
    NULL,
    read_enum,
};

// These datatypes are matched by taking the tag byte, shifting it by 5 so to only read
// the first 3 bits of the tag byte, giving it a range or 0-7 inclusive.
//
// The remaining 5 bits can then be used to store the size of the datatype, e.g. how
// many chars in a string, this therefore has a range of 0-31, if the size exceeds or
// matches this then an additional vint is added.
//
// The overview of the tag byte is therefore TTTSSSSS with T and S being type and size.
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
    uint32_t result = (tag = *in++) & 127;

    for (shift = 7; tag & 128; shift += 7)
        result |= ((tag = *in++) & 127) << shift;

    return result;
}

uint32_t read_size(void) {
    uint32_t size = tag & 31;

    if (size == 31)
        size += variable_int();

    return size;
}

SV* read_undef(pTHX) { return &PL_sv_undef; }

SV* read_true(pTHX) {
    SV *sv = Perl_newSV_type(aTHX_ SVt_IV);

    SvREFCNT(bool_true)++;
    SvROK_on(sv);
    SvRV_set(sv, bool_true);

    return sv;
}

SV* read_false(pTHX) {
    SV *sv = Perl_newSV_type(aTHX_ SVt_IV);

    SvREFCNT(bool_false)++;
    SvROK_on(sv);
    SvRV_set(sv, bool_false);

    return sv;
}

SV* read_byte(pTHX) { return Perl_newSViv(aTHX_ (int8_t) *in++); }

SV* read_short(pTHX) {
    int16_t s = in[0] << 8 | in[1];

    in += 2;

    return Perl_newSViv(aTHX_ s);
}

// For perls with double length NVs this conversion is simple.
// Read 8 bytes, cast to double, return. For long double perls
// more magic is used, see read_float for more details.
SV* read_double(pTHX) {
    int_to_double u = { (uint64_t) in[0] << 56 |
                        (uint64_t) in[1] << 48 |
                        (uint64_t) in[2] << 40 |
                        (uint64_t) in[3] << 32 |
                        (uint64_t) in[4] << 24 |
                        (uint64_t) in[5] << 16 |
                        (uint64_t) in[6] << 8  |
                        (uint64_t) in[7] };

    in += 8;

#ifdef USE_LONG_DOUBLE
    char *str = alloca(snprintf(NULL, 0, "%.14f", u.d));

    sprintf(str, "%.14f", u.d);

    return Perl_newSVnv(aTHX_ strtold(str, NULL));
#else
    return Perl_newSVnv(aTHX_ u.d);
#endif
}

SV* read_int(pTHX) {
    int32_t i = in[0] << 24 | in[1] << 16 | in[2] << 8 | in[3];

    in += 4;

    return Perl_newSViv(aTHX_ i);
}

SV* read_long(pTHX) {
    int64_t l = (uint64_t) in[0] << 56 |
                (uint64_t) in[1] << 48 |
                (uint64_t) in[2] << 40 |
                (uint64_t) in[3] << 32 |
                (uint64_t) in[4] << 24 |
                (uint64_t) in[5] << 16 |
                (uint64_t) in[6] << 8  |
                (uint64_t) in[7];

    in += 8;

    return Perl_newSViv(aTHX_ l);
}

// JavaBin has a 4byte float format, NVs in perl are either double or long double,
// therefore a little magic is required. Read the 4 bytes into an int in the
// correct endian order. Re-read these bits as a float, stringify this float,
// then finally numify the string into a double or long double.
SV* read_float(pTHX) {
    int_to_float u = { in[0] << 24 | in[1] << 16 | in[2] << 8 | in[3] };

    in += 4;

    char *str = alloca(snprintf(NULL, 0, "%f", u.f));

    sprintf(str, "%f", u.f);

#ifdef USE_LONG_DOUBLE
    long double d = strtold(str, NULL);
#else
    double d = strtod(str, NULL);
#endif

    return Perl_newSVnv(aTHX_ d);
}

SV* read_date(pTHX) {
    int64_t date_ms = (uint64_t) in[0] << 56 |
                      (uint64_t) in[1] << 48 |
                      (uint64_t) in[2] << 40 |
                      (uint64_t) in[3] << 32 |
                      (uint64_t) in[4] << 24 |
                      (uint64_t) in[5] << 16 |
                      (uint64_t) in[6] << 8  |
                      (uint64_t) in[7];

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

    uint32_t key_size, size = tag >> 5 ? read_size() : variable_int();

    while (size--) {
        uint8_t *key;

        tag = *in++;

        if ((key_size = read_size())) {
            key = cache_keys[key_size];

            key_size = cache_sizes[key_size];
        }
        else {
            tag = *in++;

            cache_sizes[++cache_pos] = key_size = read_size();

            cache_keys[cache_pos] = key = in;

            in += key_size;
        }

        tag = *in++;

        Perl_hv_common(aTHX_ hv, NULL, (char *)key, key_size, HVhek_UTF8, HV_FETCH_ISSTORE, DISPATCH, 0);
    }

    SV *rv = Perl_newSV_type(aTHX_ SVt_IV);

    SvROK_on(rv);
    SvRV_set(rv, (SV*)hv);

    return rv;
}

SV* read_solr_doc(pTHX) {
    tag = *in++;

    // Assume the doc is implemented as a simple ordered map.
    return read_map(aTHX);
}

SV* read_solr_doc_list(pTHX) {
    HV *hv = newHV();

    // Assume values are in an array, skip tag & DISPATCH.
    in++;

    // Assume numFound is a small long.
    tag = *in++;
    Perl_hv_common(aTHX_ hv, NULL, "numFound", 8, 0, HV_FETCH_ISSTORE, read_small_long(aTHX), numFound);

    // Assume start is a small long.
    tag = *in++;
    Perl_hv_common(aTHX_ hv, NULL, "start", 5, 0, HV_FETCH_ISSTORE, read_small_long(aTHX), start);

    // Assume maxScore is either a float or undef.
    Perl_hv_common(aTHX_ hv, NULL, "maxScore", 8, 0, HV_FETCH_ISSTORE, *in++ ? read_float(aTHX) : &PL_sv_undef, maxScore);

    // Assume docs are an array.
    tag = *in++;
    Perl_hv_common(aTHX_ hv, NULL, "docs", 4, 0, HV_FETCH_ISSTORE, read_array(aTHX), docs);

    SV *rv = Perl_newSV_type(aTHX_ SVt_IV);

    SvROK_on(rv);
    SvRV_set(rv, (SV*)hv);

    return rv;
}

SV* read_byte_array(pTHX) {
    AV *av = newAV();
    uint32_t size;

    if ((size = variable_int())) {
        SV **ary = safemalloc(size * sizeof(SV*)), **end = ary + size;

        AvALLOC(av) = AvARRAY(av) = ary;
        AvFILLp(av) = AvMAX(av) = size - 1;

        while (ary != end)
            *ary++ = Perl_newSViv(aTHX_ (int8_t) *in++);
    }

    SV *rv = Perl_newSV_type(aTHX_ SVt_IV);

    SvROK_on(rv);
    SvRV_set(rv, (SV*)av);

    return rv;
}

SV* read_iterator(pTHX) {
    AV *av = newAV();
    uint32_t i = 0;

    while ((tag = *in++) != 15)
        av_store(av, i++, DISPATCH);

    SV *rv = Perl_newSV_type(aTHX_ SVt_IV);

    SvROK_on(rv);
    SvRV_set(rv, (SV*)av);

    return rv;
}

SV* read_enum(pTHX) {
    tag = *in++;

    // small_int if +ve, int otherwise.
    SV *sv = DISPATCH;

    Perl_sv_upgrade(aTHX_ sv, SVt_PVMG);

    tag = *in++;

    uint32_t len = read_size();

    char *str = Perl_sv_grow(aTHX_ sv, len + 1);

    memcpy(str, in, len);

    in += len;

    str[len] = '\0';

    SvCUR_set(sv, len);

    SvFLAGS(sv) = SVf_IOK | SVp_IOK | SVs_OBJECT | SVf_POK | SVp_POK | SVt_PVMG | SVf_UTF8;

    HV *stash = Perl_gv_stashpvn(aTHX_ STR_WITH_LEN("JavaBin::Enum"), 0);

    SvREFCNT(stash)++;
    SvSTASH_set(sv, stash);

    SV *rv = Perl_newSV_type(aTHX_ SVt_IV);

    SvROK_on(rv);
    SvRV_set(rv, sv);

    return rv;
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

        do result |= ((tag = *in++) & 127) << shift;
        while (tag & 128 && (shift += 7));
    }

    return Perl_newSVuv(aTHX_ result);
}

SV* read_array(pTHX) {
    AV *av = newAV();
    uint32_t size;

    if ((size = read_size())) {
        SV **ary = safemalloc(size * sizeof(SV*)), **end = ary + size;

        AvALLOC(av) = AvARRAY(av) = ary;
        AvFILLp(av) = AvMAX(av) = size - 1;

        while (ary != end) {
            tag = *in++;
            *ary++ = DISPATCH;
        }
    }

    SV *rv = Perl_newSV_type(aTHX_ SVt_IV);

    SvROK_on(rv);
    SvRV_set(rv, (SV*)av);

    return rv;
}

void write_v_int(uint32_t i) {
    while (i & ~127) {
        *out++ = (i & 127) | 128;

        i >>= 7;
    }

    *out++ = i;
}

void write_shifted_tag(uint8_t tag, uint32_t len) {
    if (len < 31)
        *out++ = tag | len;
    else {
        *out++ = tag | 31;

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
            *out++ = 0;
            break;
        case SVt_IV:
        case SVt_PVIV: {
            int64_t i = SvIV(sv);

            if (ref) {
                if (i == 1)
                    *out++ = 1;
                else if (i == 0)
                    *out++ = 2;
                else
                    Perl_croak(aTHX_ "Invalid to_javabin input: int ref");

                return;
            }

            if (i == (int8_t) i) {
                *out++ = 3;
                *out++ = i;
            }
            else if (i == (int16_t) i) {
                *out++ = 4;
                *out++ = i >> 8;
                *out++ = i;
            }
            else if (i == (int32_t) i) {
                *out++ = 6;
                *out++ = i >> 24;
                *out++ = i >> 16;
                *out++ = i >> 8;
                *out++ = i;
            }
            else {
                *out++ = 7;
                *out++ = i >> 56;
                *out++ = i >> 48;
                *out++ = i >> 40;
                *out++ = i >> 32;
                *out++ = i >> 24;
                *out++ = i >> 16;
                *out++ = i >> 8;
                *out++ = i;
            }

            break;
        }
        case SVt_PV:
            if (ref)
                Perl_croak(aTHX_ "Invalid to_javabin input: string ref");

            STRLEN len = SvCUR(sv);

            write_shifted_tag(32, len);

            memcpy(out, SvPVX(sv), len);

            out += len;

            break;
        case SVt_PVMG: {
            char *class = HvAUX(
                ((XPVMG*) SvANY(sv))->xmg_stash
            )->xhv_name_u.xhvnameu_name->hek_key;

            if (strcmp(class, "JavaBin::Bool") == 0)
                *out++ = SvIV(sv) == 1 ? 1 : 2;
            else
                Perl_croak(aTHX_ "Invalid to_javabin input: object");

            break;
        }
        case SVt_REGEXP:
            Perl_croak(aTHX_ "Invalid to_javabin input: regex");
        case SVt_PVGV:
            Perl_croak(aTHX_ "Invalid to_javabin input: glob");
        case SVt_PVAV: {
            uint32_t size = AvFILL(sv) + 1;

            write_shifted_tag(128, size);

            SV **ary = AvARRAY(sv), **end = ary + size;

            while (ary != end)
                write_sv(aTHX_ *ary++);

            break;
        }
        case SVt_PVHV: {
            *out++ = 10;

            write_v_int(HvFILL(sv));

            HE *entry;

            while ((entry = Perl_hv_iternext_flags(aTHX_ (HV*) sv, 0))) {
                //TODO Implement the cached map key feature, reduces bin size.
                *out++ = 0;

                uint32_t len = HeKLEN(entry);

                write_shifted_tag(32, len);

                memcpy(out, HeKEY(entry), len);

                out += len;

                write_sv(aTHX_ HeVAL(entry));
            }

            break;
        }
        case SVt_PVCV:
            Perl_croak(aTHX_ "Invalid to_javabin input: sub ref");
        default:
            fprintf(stderr, "other: %d\n", SvTYPE(sv));
    }
}

void from_javabin(pTHX_ CV *cv) {
    PERL_UNUSED_VAR(cv);

    SV **sp = PL_stack_base + *PL_markstack_ptr-- + 1;

    if (sp > PL_stack_sp)
        return;

    // Zero the cache.
    // TODO zero more than just the cache index?
    cache_pos = 0;

    if (SvCUR(*sp) < 2)
        Perl_croak(aTHX_ "Invalid from_javabin input: insufficient length");

    in = (uint8_t *) SvPVX(*sp);

    if (*in++ != 2)
        Perl_croak(aTHX_ "Invalid from_javabin input: expected version 2");

    tag = *in++;

    *sp = Perl_sv_2mortal(aTHX_ DISPATCH);

    PL_stack_sp = sp;
}

void to_javabin(pTHX_ CV *cv) {
    PERL_UNUSED_VAR(cv);

    SV **sp = PL_stack_base + *PL_markstack_ptr-- + 1;

    if (sp > PL_stack_sp)
        return;

    //FIXME obviously
    uint8_t *out_start = out = malloc(1000);

    *out++ = '\2';

    write_sv(aTHX_ *sp);

    *sp = Perl_newSVpvn_flags(aTHX_ (char *)out_start, out - out_start, 0);

    free(out_start);

    PL_stack_sp = sp;
}

void deref(pTHX_ CV *cv) {
    PERL_UNUSED_VAR(cv);

    PL_stack_sp = PL_stack_base + *PL_markstack_ptr + 1;

    *PL_stack_sp = SvRV(*PL_stack_sp);
}

void sub(pTHX_ char *name, STRLEN len, XSUBADDR_t addr) {
    CV *cv = (CV*)Perl_newSV_type(aTHX_ SVt_PVCV);
    GV *gv = Perl_gv_fetchpvn_flags(aTHX_ name, len, GV_ADD, SVt_PVCV);

    CvISXSUB_on(cv);
    CvXSUB(cv) = addr;

    GvCV_set(gv, cv);
    Perl_cvgv_set(aTHX_ cv, gv);

    SvFLAGS(GvSTASH(gv)) |= SVf_AMAGIC;
}

void boot(pTHX_ CV *cv) {
    PERL_UNUSED_VAR(cv);

    sub(aTHX_ STR_WITH_LEN("JavaBin::from_javabin"), from_javabin);
    sub(aTHX_ STR_WITH_LEN("JavaBin::to_javabin"), to_javabin);
    sub(aTHX_ STR_WITH_LEN("JavaBin::Bool::()"), NULL);
    sub(aTHX_ STR_WITH_LEN("JavaBin::Bool::(bool"), deref);
    sub(aTHX_ STR_WITH_LEN("JavaBin::Enum::()"), NULL);
    sub(aTHX_ STR_WITH_LEN("JavaBin::Enum::(0+"), deref);
    sub(aTHX_ STR_WITH_LEN("JavaBin::Enum::(\"\""), deref);

    Perl_sv_setsv_flags(
        aTHX_
        GvSV(Perl_gv_fetchpvn_flags(aTHX_ STR_WITH_LEN("JavaBin::Bool::()"), GV_ADD, SVt_PV)),
        &PL_sv_yes,
        0
    );
    Perl_sv_setsv_flags(
        aTHX_
        GvSV(Perl_gv_fetchpvn_flags(aTHX_ STR_WITH_LEN("JavaBin::Enum::()"), GV_ADD, SVt_PV)),
        &PL_sv_yes,
        0
    );

    // Make two bools (true and false), store them in globals.
    HV *stash = Perl_gv_stashpvn(aTHX_ STR_WITH_LEN("JavaBin::Bool"), 0);
    SvREFCNT(stash) += 2;

    bool_true  = Perl_newSVuv(aTHX_ 1);
    bool_false = Perl_newSVuv(aTHX_ 0);

    Perl_sv_upgrade(aTHX_ bool_true,  SVt_PVMG);
    Perl_sv_upgrade(aTHX_ bool_false, SVt_PVMG);

    SvOBJECT_on(bool_true);
    SvOBJECT_on(bool_false);

    SvSTASH_set(bool_true, stash);
    SvSTASH_set(bool_false, stash);

    // Take refs to the bool and store them on the JavaBin pkg.
    SV *sv = Perl_newSV_type(aTHX_ SVt_IV);

    SvROK_on(sv);
    SvRV_set(sv, bool_true);

    Perl_sv_setsv_flags(
        aTHX_
        GvSV(Perl_gv_fetchpvn_flags(aTHX_ STR_WITH_LEN("JavaBin::true"), GV_ADD, SVt_PV)),
        sv,
        0
    );

    sv = Perl_newSV_type(aTHX_ SVt_IV);

    SvROK_on(sv);
    SvRV_set(sv, bool_false);

    Perl_sv_setsv_flags(
        aTHX_
        GvSV(Perl_gv_fetchpvn_flags(aTHX_ STR_WITH_LEN("JavaBin::false"), GV_ADD, SVt_PV)),
        sv,
        0
    );

    // Precompute some hash keys.
    PERL_HASH(docs    , "docs"    , 4);
    PERL_HASH(maxScore, "maxScore", 8);
    PERL_HASH(numFound, "numFound", 8);
    PERL_HASH(start   , "start"   , 5);
}