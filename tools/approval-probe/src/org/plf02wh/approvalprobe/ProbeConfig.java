package org.plf02wh.approvalprobe;

import android.content.Context;
import com.nimbusds.jose.jwk.ECKey;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Iterator;
import java.util.Set;
import org.json.JSONObject;

final class ProbeConfig {
    final URI relayURL;
    final String relayId, approverId, requesterId, account;
    final ECKey requesterKey;

    ProbeConfig(Context context) throws Exception {
        byte[] bytes;
        try (InputStream input = context.getAssets().open("trial.json");
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[1024];
            int count;
            while ((count = input.read(buffer)) != -1) {
                if (output.size() + count > 16384) throw new IllegalArgumentException("config_size");
                output.write(buffer, 0, count);
            }
            bytes = output.toByteArray();
        }
        JSONObject json = new JSONObject(new String(bytes, StandardCharsets.UTF_8));
        Set<String> fields = new HashSet<>(Arrays.asList("version", "relayURL", "relayId",
                "approverId", "requesterId", "account", "requesterPublicKey"));
        for (Iterator<String> keys = json.keys(); keys.hasNext();) {
            if (!fields.remove(keys.next())) throw new IllegalArgumentException("config_fields");
        }
        if (!fields.isEmpty() || !Integer.valueOf(1).equals(json.get("version")))
            throw new IllegalArgumentException("config_version");
        relayURL = new URI(string(json, "relayURL"));
        if (!"wss".equals(relayURL.getScheme()) || relayURL.getHost() == null ||
                relayURL.getUserInfo() != null || relayURL.getQuery() != null ||
                relayURL.getFragment() != null || !"/v1/relay".equals(relayURL.getPath()))
            throw new IllegalArgumentException("config_url");
        relayId = actor(json, "relayId");
        approverId = actor(json, "approverId");
        requesterId = actor(json, "requesterId");
        account = string(json, "account");
        if (!account.matches("[A-Za-z0-9_.-]{1,64}"))
            throw new IllegalArgumentException("config_account");
        JSONObject jwk = json.getJSONObject("requesterPublicKey");
        if (jwk.length() != 4 || !jwk.has("kty") || !jwk.has("crv") ||
                !jwk.has("x") || !jwk.has("y")) throw new IllegalArgumentException("config_key");
        requesterKey = ECKey.parse(jwk.toString());
        if (requesterKey.isPrivate()) throw new IllegalArgumentException("config_private_key");
    }

    private static String actor(JSONObject json, String key) throws Exception {
        String value = string(json, key);
        if (!value.matches("[A-Za-z0-9_-]{1,64}")) throw new IllegalArgumentException("config_actor");
        return value;
    }

    private static String string(JSONObject json, String key) throws Exception {
        Object value = json.get(key);
        if (!(value instanceof String)) throw new IllegalArgumentException("config_type");
        return (String) value;
    }
}
