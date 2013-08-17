import java.io.FileOutputStream;
import java.text.SimpleDateFormat;
import java.util.Arrays;
import java.util.Date;
import java.util.HashMap;
import org.apache.solr.common.util.JavaBinCodec;

public class MakeData {
    public static void main(String[] args) {
        try {
            // Bytes
            for (byte b : new byte[]{-128, 0, 127} ) {
                new JavaBinCodec().marshal(b, new FileOutputStream("data/byte-" + b));
            }

            // Shorts
            for (short s : new short[]{-32768,
                                       -129,
                                        0,
                                        128,
                                        32767} ) {
                new JavaBinCodec().marshal(s, new FileOutputStream("data/short-" + s));
            }

            // Ints
            for (int i : new int[]{-2147483648,
                                   -8388609,
                                   -32769,
                                   -129,
                                    0,
                                    128,
                                    32768,
                                    8388608,
                                    2147483647} ) {
                new JavaBinCodec().marshal(i, new FileOutputStream("data/int-" + i));
            }

            // Longs
            for (long l : new long[]{-9223372036854775808L,
                                     -36028797018963969L,
                                     -140737488355329L,
                                     -549755813889L,
                                     -2147483649L,
                                     -8388609,
                                     -32769,
                                     -129,
                                      0,
                                      128,
                                      32768,
                                      8388608,
                                      2147483648L,
                                      549755813888L,
                                      140737488355328L,
                                      36028797018963968L,
                                      9223372036854775807L} ) {
                new JavaBinCodec().marshal(l, new FileOutputStream("data/long-" + l));
            }

            // Dates
            SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");

            sdf.setTimeZone(java.util.TimeZone.getTimeZone("Zulu"));

            for (String date : new String[]{"1969-07-20T20:17:40.000Z", "1989-06-07T13:33:33.337Z"} ) {
                new JavaBinCodec().marshal(sdf.parse(date), new FileOutputStream("data/date-" + date));
            }

            // Byte arrays
            new JavaBinCodec().marshal(new byte[]{}, new FileOutputStream("data/byte_array-[]"));

            new JavaBinCodec().marshal(new byte[]{-128, 0, 127}, new FileOutputStream("data/byte_array-[qw(-128 0 127)]"));

            // Iterators
            new JavaBinCodec().marshal(Arrays.asList(new String[]{}).iterator(), new FileOutputStream("data/iterator-[]"));

            new JavaBinCodec().marshal(
                Arrays.asList(new String[]{"foo", "bar", "baz", "qux"}).iterator(),
                new FileOutputStream("data/iterator-[qw(foo bar baz qux)]")
            );

            // Arrays
            new JavaBinCodec().marshal(new String[]{}, new FileOutputStream("data/array-[]"));

            new JavaBinCodec().marshal(
                new String[]{"foo", "bar", "baz", "qux"},
                new FileOutputStream("data/array-[qw(foo bar baz qux)]")
            );

            // Strings
            for (String str : new String[]{"", "Grüßen", "The quick brown fox jumped over the lazy dog", "☃"}) {
                 new JavaBinCodec().marshal(str, new FileOutputStream("data/string-" + str));
            }

            // Hash maps
            new JavaBinCodec().marshal(new HashMap(), new FileOutputStream("data/hash_map-{}"));

            new JavaBinCodec().marshal(new HashMap<String, Object>(){{
                put("foo", "bar");
                put("baz", "qux");
            }}, new FileOutputStream("data/hash_map-{qw(foo bar baz qux)}"));

            new JavaBinCodec().marshal(new HashMap<String, Object>(){{
                put("foo", "bar");
                put("bar", "foo");
            }}, new FileOutputStream("data/hash_map-{qw(foo bar bar foo)}"));

            // All together now
            new JavaBinCodec().marshal(new HashMap<String, Object>(){{
                put("array", new String[]{"foo", "bar", "baz", "qux"});
                put("byte", (byte)127);
                put("byte_array", new byte[]{-128, 0, 127});
                put("byte_neg", (byte)-128);
                put("iterator", Arrays.asList(new String[]{"qux", "baz", "bar", "foo"}).iterator());
                put("false", false);
                put("null", null);
                put("pangram", "The quick brown fox jumped over the lazy dog");
                put("short", (short)32_767);
                put("short_neg", (short)-32_768);
                put("snowman", "☃");
                put("true", true);
            }}, new FileOutputStream("data/all"));
        }
        catch (Exception e){
            System.out.println(e);
        }
    }
}
