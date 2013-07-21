#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

uint8_t *bytes, pos, tag;

// Lucene variable-length +ve integer, the MSB indicates whether you need another octet.
// http://lucene.apache.org/core/old_versioned_docs/versions/3_5_0/fileformats.html#VInt
uint32_t variable_int(void) {
    uint8_t shift;
    uint32_t result = ( tag = bytes[pos++] ) & 127;

    for (shift = 7; tag & 128; shift += 7)
        result |= ((uint32_t)((tag = bytes[pos++]) & 127)) << shift;

    return result;
}

// Like above, this is the long variant.
uint64_t variable_long(void) {
    uint8_t shift;
    uint64_t result = ( tag = bytes[pos++] ) & 127;

    for (shift = 7; tag & 128; shift += 7)
        result |= ((uint64_t)((tag = bytes[pos++]) & 127)) << shift;

    return result;
}

SV* read_undef(void) { return newSV(0); }

SV* read_bool_true(void) { return newSVuv(1); }

SV* read_bool_false(void) { return newSVuv(0); }

SV* read_byte(void) { return newSViv( (int8_t) bytes[pos++] ); }

SV* read_short(void) {
    pos += 2;

    return newSViv( (int16_t) ( ( bytes[pos - 2] << 8 ) | bytes[pos - 1] ) );
}

SV* read_double(void) { return newSVuv(0); }

SV* read_int(void) {
    // This is from network (big) endian to intel (little) endian.
    // TODO test/write alternative for POWER PC (big)
    pos += 4;

    return newSViv( (int32_t) ( ( bytes[pos - 4] << 24 ) |
                                ( bytes[pos - 3] << 16 ) |
                                ( bytes[pos - 2] << 8  ) |
                                ( bytes[pos - 1] ) ) );
}

SV* read_long(void) {
    pos += 8;

    return newSViv( (int64_t) ( ( (uint64_t) bytes[pos - 8] << 56 ) |
                                ( (uint64_t) bytes[pos - 7] << 48 ) |
                                ( (uint64_t) bytes[pos - 6] << 40 ) |
                                ( (uint64_t) bytes[pos - 5] << 32 ) |
                                ( (uint64_t) bytes[pos - 4] << 24 ) |
                                ( (uint64_t) bytes[pos - 3] << 16 ) |
                                ( (uint64_t) bytes[pos - 2] << 8  ) |
                                ( (uint64_t) bytes[pos - 1] ) ) );
}

SV* read_float(void) { return newSVuv(0); }

SV* read_date(void) {
    pos += 8;

    uint64_t date_ms = ( ( (uint64_t) bytes[pos - 8] << 56 ) |
                         ( (uint64_t) bytes[pos - 7] << 48 ) |
                         ( (uint64_t) bytes[pos - 6] << 40 ) |
                         ( (uint64_t) bytes[pos - 5] << 32 ) |
                         ( (uint64_t) bytes[pos - 4] << 24 ) |
                         ( (uint64_t) bytes[pos - 3] << 16 ) |
                         ( (uint64_t) bytes[pos - 2] << 8  ) |
                         ( (uint64_t) bytes[pos - 1] ) );

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

SV* read_byte_array(void) {
    AV *array = newAV();

    uint32_t i;
    uint32_t size = variable_int();

    for ( i = 0; i < size; i++ )
        av_store(array, i, newSViv( (int8_t) bytes[pos++] ));

    return newRV_noinc((SV*) array);
}

SV* read_string(void) {
    uint32_t length = tag & 31;

    if ( length == 31 )
        length += variable_int();

    SV *string = newSVpv(bytes + pos, length);

    pos += length;

    SvUTF8_on(string);

    return string;
}

SV* read_small_int(void) {
    uint32_t result = tag & 15;

    if (tag & 16)
        result = (variable_int() << 4) | result;

    return newSVuv(result);
}

SV* read_small_long(void) {
    uint64_t result = tag & 15;

    if (tag & 16)
        result = (variable_long() << 4) | result;

    return newSVuv(result);
}

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
    NULL,
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
SV *(*dispatch_shift[4])(void) = {
    NULL,
    read_string,
    read_small_int,
    read_small_long,
};

MODULE = JavaBin PACKAGE = JavaBin

SV *from_javabin(input)
    unsigned char *input
    PROTOTYPE: $
    CODE:
        bytes = input;
        pos = 1;

        tag = bytes[pos++];

        //fprintf(stderr, "type = %d or %d\n", tag >> 5, tag);

        RETVAL = tag >> 5 ? dispatch_shift[tag >> 5]() : dispatch[tag]();
    OUTPUT: RETVAL
