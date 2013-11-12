#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define DISPATCH tag >> 5 ? dispatch_shift[tag >> 5](aTHX) : dispatch[tag](aTHX)

// TODO non fixed cache size?
uint8_t *bytes, *cache_keys[100], cache_pos, tag;
int32_t cache_sizes[100];

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
    uint32_t result = (tag = *(bytes++)) & 127;

    for (shift = 7; tag & 128; shift += 7)
        result |= ((uint32_t)((tag = *(bytes++)) & 127)) << shift;

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

SV* read_byte(pTHX) { return Perl_newSViv(aTHX_ (int8_t) *(bytes++)); }

SV* read_short(pTHX) {
    bytes += 2;

    return Perl_newSViv(aTHX_ (int16_t) ( ( *(bytes - 2) << 8 ) | *(bytes - 1)) );
}

SV* read_double(pTHX) {
    uint64_t i = ( ( (uint64_t) *bytes << 56 ) |
                   ( (uint64_t) *(bytes + 1) << 48 ) |
                   ( (uint64_t) *(bytes + 2) << 40 ) |
                   ( (uint64_t) *(bytes + 3) << 32 ) |
                   ( (uint64_t) *(bytes + 4) << 24 ) |
                   ( (uint64_t) *(bytes + 5) << 16 ) |
                   ( (uint64_t) *(bytes + 6) << 8  ) |
                   ( (uint64_t) *(bytes + 7) ) );

    bytes += 8;

    return Perl_newSVnv(aTHX_ *(double*)&i);
}

SV* read_int(pTHX) {
    // This is from network (big) endian to intel (little) endian.
    // TODO test/write alternative for POWER PC (big)
    bytes += 4;

    return Perl_newSViv(aTHX_ (int32_t) ( ( *(bytes - 4) << 24 ) |
                                          ( *(bytes - 3) << 16 ) |
                                          ( *(bytes - 2) << 8  ) |
                                          ( *(bytes - 1) ) ) );
}

SV* read_long(pTHX) {
    bytes += 8;

    return Perl_newSViv(aTHX_ (int64_t) ( ( (uint64_t) *(bytes - 8) << 56 ) |
                                          ( (uint64_t) *(bytes - 7) << 48 ) |
                                          ( (uint64_t) *(bytes - 6) << 40 ) |
                                          ( (uint64_t) *(bytes - 5) << 32 ) |
                                          ( (uint64_t) *(bytes - 4) << 24 ) |
                                          ( (uint64_t) *(bytes - 3) << 16 ) |
                                          ( (uint64_t) *(bytes - 2) << 8  ) |
                                          ( (uint64_t) *(bytes - 1) ) ) );
}

// JavaBin has a 4byte float format, decimal values in Perl are always doubles,
// therefore a little magic is required. Read the 4 bytes into an int in the
// correct endian order. Re-read these bits as a float, stringify this float,
// then finally numify the string into a double.
SV* read_float(pTHX) {
    uint32_t i = ( ( *bytes       << 24 ) |
                   ( *(bytes + 1) << 16 ) |
                   ( *(bytes + 2) << 8  ) |
                   ( *(bytes + 3) ) );

    bytes += 4;

    char buffer[47];

    sprintf(buffer, "%f", *(float*)&i);

    return Perl_newSVnv(aTHX_ strtod(buffer, NULL));
}

SV* read_date(pTHX) {
    int64_t date_ms = ( ( (uint64_t) *bytes       << 56 ) |
                        ( (uint64_t) *(bytes + 1) << 48 ) |
                        ( (uint64_t) *(bytes + 2) << 40 ) |
                        ( (uint64_t) *(bytes + 3) << 32 ) |
                        ( (uint64_t) *(bytes + 4) << 24 ) |
                        ( (uint64_t) *(bytes + 5) << 16 ) |
                        ( (uint64_t) *(bytes + 6) << 8  ) |
                        ( (uint64_t) *(bytes + 7) ) );

    bytes += 8;

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

    return Perl_newSVpv(aTHX_ date_str, 24);
}

SV* read_map(pTHX) {
    HV *hv = newHV();

    uint32_t i, key_size, size = tag >> 5 ? read_size() : variable_int();

    for ( i = 0; i < size; i++ ) {
        uint8_t *key;

        tag = *(bytes++);

        if ( key_size = read_size() ) {
            key = cache_keys[key_size];

            key_size = cache_sizes[key_size];
        }
        else {
            tag = *(bytes++);

            cache_sizes[++cache_pos] = key_size = read_size();

            cache_keys[cache_pos] = key = bytes;

            bytes += key_size;
        }

        tag = *(bytes++);

        Perl_hv_common(aTHX_ hv, NULL, key, key_size, 0, HV_FETCH_ISSTORE, DISPATCH, 0);
    }

    return Perl_newRV_noinc(aTHX_ (SV*) hv);
}

SV* read_solr_doc(pTHX) {
    tag = *(bytes++);

    // Assume the doc is implemented as a simple ordered map.
    return read_map(aTHX);
}

SV* read_solr_doc_list(pTHX) {
    HV *hv = newHV();

    // Assume values are in an array, skip tag & DISPATCH.
    bytes++;

    // Assume numFound is a small long.
    tag = *(bytes++);
    Perl_hv_common(aTHX_ hv, NULL, STR_WITH_LEN("numFound"), 0, HV_FETCH_ISSTORE, read_small_long(aTHX), 0);

    // Assume start is a small long.
    tag = *(bytes++);
    Perl_hv_common(aTHX_ hv, NULL, STR_WITH_LEN("start"), 0, HV_FETCH_ISSTORE, read_small_long(aTHX), 0);

    // Assume maxScore is either a float or undef.
    tag = *(bytes++);
    Perl_hv_common(aTHX_ hv, NULL, STR_WITH_LEN("maxScore"), 0, HV_FETCH_ISSTORE, tag ? read_float(aTHX) : &PL_sv_undef, 0);

    // Assume docs are an array.
    tag = *(bytes++);
    Perl_hv_common(aTHX_ hv, NULL, STR_WITH_LEN("docs"), 0, HV_FETCH_ISSTORE, read_array(aTHX), 0);

    return Perl_newRV_noinc(aTHX_ (SV*) hv);
}

SV* read_byte_array(pTHX) {
    AV *av = newAV();
    uint32_t i, size = variable_int();

    for ( i = 0; i < size; i++ )
        av_store(av, i, newSViv((int8_t) *(bytes++)));

    return Perl_newRV_noinc(aTHX_ (SV*) av);
}

SV* read_iterator(pTHX) {
    AV *av = newAV();
    uint32_t i = 0;

    while ( ( tag = *(bytes++) ) != 15 )
        av_store(av, i++, DISPATCH);

    return Perl_newRV_noinc(aTHX_ (SV*) av);
}

SV* read_string(pTHX) {
    uint32_t size = read_size();

    SV *string = Perl_newSVpvn_flags(aTHX_ bytes, size, SVf_UTF8);

    bytes += size;

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

        do result |= ((uint64_t)((tag = *(bytes++)) & 127)) << shift;
        while (tag & 128 && (shift += 7));
    }

    return Perl_newSVuv(aTHX_ result);
}

SV* read_array(pTHX) {
    AV *av = newAV();

    uint32_t i, size = read_size();

    for ( i = 0; i < size; i++ ) {
        tag = *(bytes++);

        Perl_av_store(aTHX_ av, i, DISPATCH);
    }

    return Perl_newRV_noinc(aTHX_ (SV*) av);
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

    // Set bytes, skip the version byte.
    bytes = (uint8_t *) SvPV_nolen(ST(0)) + 1;

    tag = *(bytes++);

    //fprintf(stderr, "type = %d or %d\n", tag >> 5, tag);

    ST(0) = Perl_sv_2mortal(aTHX_ DISPATCH);

    XSRETURN(1);

MODULE = JavaBin PACKAGE = JavaBin::Bool
FALLBACK: TRUE

void overload(...)
OVERLOAD: 0+ \"\"
PPCODE:
    ST(0) = SvRV(ST(0));

    XSRETURN(1);
