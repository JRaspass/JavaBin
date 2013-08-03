#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define DISPATCH tag >> 5 ? dispatch_shift[tag >> 5]() : dispatch[tag]()

uint8_t *bytes, cache_pos, tag;

// FIXME cache should dynamically size.
SV *cache[100];

SV* read_undef(void);
SV* read_bool_true(void);
SV* read_bool_false(void);
SV* read_byte(void);
SV* read_short(void);
SV* read_double(void);
SV* read_int(void);
SV* read_long(void);
SV* read_float(void);
SV* read_date(void);
SV* read_hash(void);
SV* read_byte_array(void);

SV *(*dispatch[14])(void) = {
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
    read_hash,
    NULL,
    NULL,
    read_byte_array,
};

/* These datatypes are matched by taking the tag byte, shifting it by 5 so to only read
   the first 3 bits of the tag byte, giving it a range or 0-7 inclusive.

   The remaining 5 bits can then be used to store the size of the datatype, e.g. how
   many chars in a string, this therefore has a range of 0-31, if the size exceeds or
   matches this then an additional vint is added.

   The overview of the tag byte is therefore TTTSSSSS with T and S being type and size. */
SV* read_string(void);
SV* read_small_int(void);
SV* read_small_long(void);
SV* read_extern_string(void);

SV *(*dispatch_shift[8])(void) = {
    NULL,
    read_string,
    read_small_int,
    read_small_long,
    NULL,
    NULL,
    NULL,
    read_extern_string,
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

SV* read_undef(void) { return newSV(0); }

SV* read_bool_true(void) { return newSVuv(1); }

SV* read_bool_false(void) { return newSVuv(0); }

SV* read_byte(void) { return newSViv((int8_t) *(bytes++)); }

SV* read_short(void) {
    bytes += 2;

    return newSViv( (int16_t) ( ( *(bytes - 2) << 8 ) | *(bytes - 1) ) );
}

SV* read_double(void) { return newSVuv(0); }

SV* read_int(void) {
    // This is from network (big) endian to intel (little) endian.
    // TODO test/write alternative for POWER PC (big)
    bytes += 4;

    return newSViv( (int32_t) ( ( *(bytes - 4) << 24 ) |
                                ( *(bytes - 3) << 16 ) |
                                ( *(bytes - 2) << 8  ) |
                                ( *(bytes - 1) ) ) );
}

SV* read_long(void) {
    bytes += 8;

    return newSViv( (int64_t) ( ( (uint64_t) *(bytes - 8) << 56 ) |
                                ( (uint64_t) *(bytes - 7) << 48 ) |
                                ( (uint64_t) *(bytes - 6) << 40 ) |
                                ( (uint64_t) *(bytes - 5) << 32 ) |
                                ( (uint64_t) *(bytes - 4) << 24 ) |
                                ( (uint64_t) *(bytes - 3) << 16 ) |
                                ( (uint64_t) *(bytes - 2) << 8  ) |
                                ( (uint64_t) *(bytes - 1) ) ) );
}

SV* read_float(void) { return newSVuv(0); }

SV* read_date(void) {
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

    return newSVpv(date_str, 24);
}

SV* read_hash(void) {
    HV *hash = newHV();

    uint32_t i, size = variable_int();

    for ( i = 0; i < size; i++ ) {
        tag = *(bytes++);

        SV *key = DISPATCH;

        tag = *(bytes++);

        SV *value = DISPATCH;

        hv_store_ent(hash, key, value, 0);
    }

    return newRV_noinc((SV*) hash);
}

SV* read_byte_array(void) {
    AV *array = newAV();
    uint32_t i, size = variable_int();

    for ( i = 0; i < size; i++ )
        av_store(array, i, newSViv((int8_t) *(bytes++)));

    return newRV_noinc((SV*) array);
}

SV* read_string(void) {
    uint32_t size = read_size();

    SV *string = newSVpv(bytes, size);

    bytes += size;

    SvUTF8_on(string);

    return string;
}

SV* read_small_int(void) {
    uint32_t result = tag & 15;

    if (tag & 16)
        result |= variable_int() << 4;

    return newSVuv(result);
}

SV* read_small_long(void) {
    uint64_t result = tag & 15;

    // Inlined variable-length +ve long code, see variable_int().
    if (tag & 16) {
        uint8_t shift = 4;

        do result |= ((uint64_t)((tag = *(bytes++)) & 127)) << shift;
        while (tag & 128 && (shift += 7));
    }

    return newSVuv(result);
}

SV* read_extern_string(void) {
    SV *string;

    uint32_t size = read_size();

    if (size) {
        string = cache[size - 1];
    }
    else {
        tag = *(bytes++);

        cache[cache_pos++] = string = DISPATCH;
    }

    return string;
}

MODULE = JavaBin PACKAGE = JavaBin

SV *from_javabin(input)
    unsigned char *input
    PROTOTYPE: DISABLE
    CODE:
        // Skip the version byte.
        bytes = input + 1;

        tag = *(bytes++);

        //fprintf(stderr, "type = %d or %d\n", tag >> 5, tag);

        RETVAL = DISPATCH;
    OUTPUT: RETVAL
