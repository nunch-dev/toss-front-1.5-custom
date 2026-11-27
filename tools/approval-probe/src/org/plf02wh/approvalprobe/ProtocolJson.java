package org.plf02wh.approvalprobe;

import com.nimbusds.jose.shaded.gson.Strictness;
import com.nimbusds.jose.shaded.gson.stream.JsonReader;
import com.nimbusds.jose.shaded.gson.stream.JsonToken;
import com.nimbusds.jose.util.Base64URL;
import java.io.IOException;
import java.io.StringReader;
import java.math.BigDecimal;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.Map;

/** Strict decoding for the protocol's flat JSON objects, using Nimbus's shaded Gson. */
final class ProtocolJson {
    static final long MAX_INTEGER = 9007199254740991L;
    private ProtocolJson() {}

    static byte[] decode(String encoded) throws ApprovalProtocol.ProtocolException {
        if (!encoded.matches("[A-Za-z0-9_-]+")) throw error("invalid_token");
        byte[] bytes = new Base64URL(encoded).decode();
        if (!Base64URL.encode(bytes).toString().equals(encoded)) throw error("invalid_token");
        return bytes;
    }

    static Map<String, Object> object(byte[] bytes, String code)
            throws ApprovalProtocol.ProtocolException {
        final String text;
        try {
            text = StandardCharsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(bytes)).toString();
        } catch (CharacterCodingException e) {
            throw error(code);
        }
        Map<String, Object> fields = new LinkedHashMap<>();
        try (JsonReader reader = new JsonReader(new StringReader(text))) {
            reader.setStrictness(Strictness.STRICT);
            // Gson accepts a BOM; it is not part of the JSON grammar.
            if (text.startsWith("\ufeff")) throw error(code);
            reader.beginObject();
            while (reader.hasNext()) {
                String name = reader.nextName();
                if (fields.containsKey(name)) throw error(code);
                JsonToken type = reader.peek();
                if (type == JsonToken.STRING) {
                    fields.put(name, reader.nextString());
                } else if (type == JsonToken.NUMBER) {
                    long value = new BigDecimal(reader.nextString()).longValueExact();
                    if (value < 0 || value > MAX_INTEGER) throw error(code);
                    fields.put(name, value);
                } else {
                    throw error(code);
                }
            }
            reader.endObject();
            if (reader.peek() != JsonToken.END_DOCUMENT) throw error(code);
            return fields;
        } catch (IOException | IllegalStateException | ArithmeticException | NumberFormatException e) {
            throw error(code);
        }
    }

    static void fields(Map<String, Object> object, String code, String... names)
            throws ApprovalProtocol.ProtocolException {
        if (!object.keySet().equals(new HashSet<>(Arrays.asList(names)))) throw error(code);
    }

    static String string(Map<String, Object> object, String name)
            throws ApprovalProtocol.ProtocolException {
        Object value = object.get(name);
        if (!(value instanceof String)) throw error("invalid_message");
        return (String) value;
    }

    static long integer(Map<String, Object> object, String name)
            throws ApprovalProtocol.ProtocolException {
        Object value = object.get(name);
        if (!(value instanceof Long)) throw error("invalid_message");
        return (Long) value;
    }

    static void matches(String value, String pattern) throws ApprovalProtocol.ProtocolException {
        if (value == null || !value.matches(pattern)) throw error("invalid_message");
    }

    static ApprovalProtocol.ProtocolException error(String code) {
        return new ApprovalProtocol.ProtocolException(code);
    }
}
