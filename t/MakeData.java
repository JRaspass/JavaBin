import java.io.FileOutputStream;
import java.text.SimpleDateFormat;
import java.util.Arrays;
import java.util.Date;
import java.util.HashMap;
import org.apache.solr.common.util.JavaBinCodec;

public class MakeData {
    public static void main(String[] args) {
        JavaBinCodec jbc = new JavaBinCodec();

        try {
            for (byte b : new byte[]{-128, 0, 127} ) {
                jbc.marshal(b, new FileOutputStream("data/byte-" + b));
            }

            for (short s : new short[]{-32768,
                                       -129,
                                        0,
                                        128,
                                        32767} ) {
                jbc.marshal(s, new FileOutputStream("data/short-" + s));
            }

            for (int i : new int[]{-2147483648,
                                   -8388609,
                                   -32769,
                                   -129,
                                    0,
                                    128,
                                    32768,
                                    8388608,
                                    2147483647} ) {
                jbc.marshal(i, new FileOutputStream("data/int-" + i));
            }

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
                jbc.marshal(l, new FileOutputStream("data/long-" + l));
            }

            SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");

            sdf.setTimeZone(java.util.TimeZone.getTimeZone("Zulu"));

            for (String date : new String[]{"1989-06-07T13:33:33.337Z"} ) {
                jbc.marshal(sdf.parse(date), new FileOutputStream("data/date-" + date));
            }

            jbc.marshal(new byte[]{-128, 0, 127}, new FileOutputStream("data/byte_array"));

            for (String str : new String[]{"", "Grüßen", "The quick brown fox jumped over the lazy dog"}) {
                 jbc.marshal(str, new FileOutputStream("data/string-" + str));
            }

            jbc.marshal(new HashMap<String, Object>(){{
                put("array", new String[]{"foo", "bar", "baz", "qux"});
                put("byte", (byte)127);
                put("byte_array", new byte[]{-128, 0, 127});
                put("byte_neg", (byte)-128);
                put("double", 1.797_693_134_862_31e308);
                put("iterator", Arrays.asList(new String[]{"qux", "baz", "bar", "foo"}).iterator());
                put("false", false);
                put("float", 3.402_823_466_385_29e+38f);
                put("shifted_sint", 2_147_483_647);
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
