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
                        addField("byte_arr", new byte[]{-128, 0, 127});
                        addField("byte_max", (byte)127);
                        addField("byte_min", (byte)-128);
                        addField("byte_zero", (byte)0);
                        addField("enum_max", new EnumFieldValue(2147483647, "max"));
                        addField("enum_min", new EnumFieldValue(-2147483648, "min"));
                        addField("enum_snowman", new EnumFieldValue(123, "☃"));
                        addField("enum_zero", new EnumFieldValue(0, "zero"));
                        addField("false", false);
                        addField("hash_map", new HashMap<String, Object>(){{
                            put("foo", "bar");
                            put("baz", "qux");
                        }});
                        addField("iterator", Arrays.asList(arr).iterator());
                        addField("named_list", new NamedList(){{
                            add("foo", "bar");
                            add("baz", "qux");
                        }});
                        addField("null", null);
                        addField("one_small_step", new Date(-14159040000L));
                        addField("pangram", "The quick brown fox jumped over the lazy dog");
                        addField("pi_double", 3.14159265358979);
                        addField("pi_float", 3.14159f);
                        addField("short_max", (short)32_767);
                        addField("short_min", (short)-32_768);
                        addField("simple_ordered_map", new SimpleOrderedMap(){{
                            add("foo", "bar");
                            add("baz", "qux");
                        }});
                        addField("snowman", "☃");
                        addField("str_arr", arr);
                        addField("true", true);
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
