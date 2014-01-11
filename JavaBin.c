#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"

#define DISPATCH tag >> 5 ? dispatch_shift[tag >> 5](aTHX) : dispatch[tag](aTHX)

typedef SV* (*FP)(pTHX);

typedef union { uint64_t i; double d; } int_to_double;
typedef union { uint32_t i; float  f; } int_to_float;

// TODO non fixed cache size?
static uint8_t *cache_keys[100], cache_pos, *in, *out, tag;
static uint32_t cache_sizes[100];

// Computed at boot hash keys.
static uint32_t docs, maxScore, numFound, start;

// Globally stored JavaBin::Bool's of true and false.
static SV *bool_true, *bool_false;

static HV* bool_stash;

// Lucene variable-length +ve integer, the MSB indicates whether you need another octet.
// http://lucene.apache.org/core/old_versioned_docs/versions/3_5_0/fileformats.html#VInt
static uint32_t read_v_int() {
    uint8_t shift;
    uint32_t result = (tag = *in++) & 127;

    for (shift = 7; tag & 128; shift += 7)
        result |= ((tag = *in++) & 127) << shift;

    return result;
}

static uint32_t read_size() {
    uint32_t size = tag & 31;

    if (size == 31)
        size += read_v_int();

    return size;
}

// Functions to read the various JavaBin datatypes and return a Perl SV.
static SV* read_undef(pTHX);
static SV* read_true(pTHX);
static SV* read_false(pTHX);
static SV* read_byte(pTHX);
static SV* read_short(pTHX);
static SV* read_double(pTHX);
static SV* read_int(pTHX);
static SV* read_long(pTHX);
static SV* read_float(pTHX);
static SV* read_date(pTHX);
static SV* read_map(pTHX);
static SV* read_solr_doc(pTHX);
static SV* read_solr_doc_list(pTHX);
static SV* read_byte_array(pTHX);
static SV* read_iterator(pTHX);
static SV* read_enum(pTHX);
static SV* read_string(pTHX);
static SV* read_small_int(pTHX);
static SV* read_small_long(pTHX);
static SV* read_array(pTHX);

static const FP dispatch[] = {
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
static const FP dispatch_shift[] = {
    NULL,
    read_string,
    read_small_int,
    read_small_long,
    read_array,
    read_map,
    read_map,
};

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
    HV *hv = (HV*)Perl_newSV_type(aTHX_ SVt_PVHV);

    uint32_t key_size, size = tag >> 5 ? read_size() : read_v_int();

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
    HV *hv = (HV*)Perl_newSV_type(aTHX_ SVt_PVHV);

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
    AV *av = (AV*)Perl_newSV_type(aTHX_ SVt_PVAV);
    uint32_t size;

    if ((size = read_v_int())) {
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
    AV *av = (AV*)Perl_newSV_type(aTHX_ SVt_PVAV);
    uint32_t i = 0;

    while ((tag = *in++) != 15)
        Perl_av_store(aTHX_ av, i++, DISPATCH);

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
        result |= read_v_int() << 4;

    return Perl_newSVuv(aTHX_ result);
}

SV* read_small_long(pTHX) {
    uint64_t result = tag & 15;

    // Inlined variable-length +ve long code, see read_v_int().
    if (tag & 16) {
        uint8_t shift = 4;

        do result |= ((tag = *in++) & 127) << shift;
        while (tag & 128 && (shift += 7));
    }

    return Perl_newSVuv(aTHX_ result);
}

SV* read_array(pTHX) {
    AV *av = (AV*)Perl_newSV_type(aTHX_ SVt_PVAV);
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

static void write_v_int(uint32_t i) {
    while (i & ~127) {
        *out++ = (i & 127) | 128;

        i >>= 7;
    }

    *out++ = i;
}

static void write_shifted_tag(uint8_t tag, uint32_t len) {
    if (len < 31)
        *out++ = tag | len;
    else {
        *out++ = tag | 31;

        write_v_int(len - 31);
    }
}

static void write_sv(pTHX_ SV *sv) {
    SvGETMAGIC(sv);

    if (SvPOKp(sv)) {
        STRLEN len = SvCUR(sv);

        write_shifted_tag(32, len);

        memcpy(out, SvPVX(sv), len);

        out += len;
    }
    else if (SvNOKp(sv)) {
        Perl_croak(aTHX_ "TODO: to_javabin double");
    }
    else if (SvIOKp(sv)) {
        int64_t i = SvIV(sv);

        if (i == (int8_t)i) {
            *out++ = 3;
            *out++ = i;
        }
        else if (i == (int16_t)i) {
            *out++ = 4;
            *out++ = i >> 8;
            *out++ = i;
        }
        else if (i == (int32_t)i) {
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
    }
    else if (SvROK(sv)) {
        sv = SvRV(sv);

        // If we have a JavaBin::Bool.
        if (SvTYPE(sv) == SVt_IV || SvSTASH(sv) == bool_stash) {
            *out++ = SvIV(sv) ? 1 : 2;

            return;
        }

        switch (SvTYPE(sv)) {
            case SVt_PVAV: {
                uint32_t len = AvFILLp(sv) + 1;

                write_shifted_tag(128, len);

                SV **ary = AvARRAY(sv), **end = ary + len;

                while (ary != end)
                    write_sv(aTHX_ *ary++);

                break;
            }
            case SVt_PVHV: {
                *out++ = 10;

                uint32_t len;

                if ((len = HvUSEDKEYS(sv))) {
                    write_v_int(len);

                    HE **start = HvARRAY(sv), **end = start + HvMAX(sv) + 1;

                    do {
                        HE *entry;

                        for (entry = *start++; entry; entry = HeNEXT(entry)) {
                            SV *value = HeVAL(entry);

                            if (value != &PL_sv_placeholder) {
                                //TODO Implement the cached key feature.
                                *out++ = 0;

                                uint32_t klen = HeKLEN(entry);

                                write_shifted_tag(32, klen);

                                memcpy(out, HeKEY(entry), klen);

                                out += klen;

                                write_sv(aTHX_ value);

                                if (--len == 0)
                                    return;
                            }
                        }
                    } while (start != end);
                }
                else
                    *out++ = 0;

                break;
            }
            default:
                *out++ = 0;
        }
    }
    else
        *out++ = 0;
}

static void from_javabin(pTHX_ CV *cv) {
    PERL_UNUSED_VAR(cv);

    SV **sp = PL_stack_base + *PL_markstack_ptr + 1;

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

static void to_javabin(pTHX_ CV *cv) {
    PERL_UNUSED_VAR(cv);

    SV **sp = PL_stack_base + *PL_markstack_ptr + 1;

    SV *targ = PAD_SV(PL_op->op_targ);

    Perl_sv_grow(aTHX_ targ, 1000); //FIXME obviously.
    SvPOK_on(targ);

    out = (uint8_t *)SvPVX(targ);

    *out++ = 2;

    write_sv(aTHX_ *sp);

    SvCUR(targ) = out - (uint8_t *)SvPVX(targ);

    *sp = targ;

    PL_stack_sp = sp;
}

static void deref(pTHX_ CV *cv) {
    PERL_UNUSED_VAR(cv);

    PL_stack_sp = PL_stack_base + *PL_markstack_ptr + 1;

    *PL_stack_sp = SvRV(*PL_stack_sp);
}

static void sub(pTHX_ char *name, STRLEN len, XSUBADDR_t addr) {
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
    bool_stash = Perl_gv_stashpvn(aTHX_ STR_WITH_LEN("JavaBin::Bool"), 0);
    SvREFCNT(bool_stash) += 2;

    bool_true  = Perl_newSVuv(aTHX_ 1);
    bool_false = Perl_newSVuv(aTHX_ 0);

    Perl_sv_upgrade(aTHX_ bool_true,  SVt_PVMG);
    Perl_sv_upgrade(aTHX_ bool_false, SVt_PVMG);

    SvOBJECT_on(bool_true);
    SvOBJECT_on(bool_false);

    SvREFCNT(bool_true)--;
    SvREFCNT(bool_false)--;

    SvSTASH_set(bool_true, bool_stash);
    SvSTASH_set(bool_false, bool_stash);

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
    PERL_HASH(docs,     "docs",     4);
    PERL_HASH(maxScore, "maxScore", 8);
    PERL_HASH(numFound, "numFound", 8);
    PERL_HASH(start,    "start",    5);
}
