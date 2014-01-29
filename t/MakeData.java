import java.util.*;
import org.apache.solr.common.*;
import org.apache.solr.common.util.*;

public class MakeData {
    public static void main(String[] args) {
        final String[] arr = new String[]{"foo", "bar", "baz", "qux"};

        try {
            new JavaBinCodec().marshal(
                new SolrDocumentList(){{
                    add(new SolrDocument(){{
                        put("byte_arr", new byte[]{-128, 0, 127});
                        put("byte_max", (byte)127);
                        put("byte_min", (byte)-128);
                        put("byte_zero", (byte)0);
                        put("enum_max", new EnumFieldValue(2147483647, "max"));
                        put("enum_min", new EnumFieldValue(-2147483648, "min"));
                        put("enum_snowman", new EnumFieldValue(123, "☃"));
                        put("enum_zero", new EnumFieldValue(0, "zero"));
                        put("false", false);
                        put("hash_map", new HashMap<String, Object>(){{
                            put("foo", "bar");
                            put("baz", "qux");
                        }});
                        put("iterator", Arrays.asList(arr).iterator());
                        put("named_list", new NamedList<String>(){{
                            add("foo", "bar");
                            add("baz", "qux");
                        }});
                        put("null", null);
                        put("one_small_step", new Date(-14159040000L));
                        put("pangram", "The quick brown fox jumped over the lazy dog");
                        put("pi_double", 3.14159265358979);
                        put("pi_float", 3.141593f);
                        put("short_max", (short)32_767);
                        put("short_min", (short)-32_768);
                        put("simple_ordered_map", new SimpleOrderedMap<String>(){{
                            add("foo", "bar");
                            add("baz", "qux");
                        }});
                        put("snowman", "☃");
                        put("str_arr", arr);
                        put("true", true);
                    }});
                    setMaxScore(0.1f);
                    setNumFound(2);
                    setStart(3);
                }}, System.out
            );
        }
        catch (Exception e){
            System.out.println(e);
        }
    }
}
