package org.plf02wh.approvalprobe;

import android.content.Context;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import com.nimbusds.jose.jwk.Curve;
import com.nimbusds.jose.jwk.ECKey;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.interfaces.ECPublicKey;
import java.security.spec.ECGenParameterSpec;

final class DeviceIdentity {
    private static final String ALIAS = "approval-probe-v1";
    final PrivateKey signingKey;

    DeviceIdentity(Context context) throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore");
        store.load(null);
        if (!store.containsAlias(ALIAS)) {
            KeyPairGenerator generator = KeyPairGenerator.getInstance(
                    KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore");
            generator.initialize(new KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN)
                    .setAlgorithmParameterSpec(new ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256)
                    .build());
            generator.generateKeyPair();
        }
        signingKey = (PrivateKey) store.getKey(ALIAS, null);
        ECPublicKey publicKey = (ECPublicKey) store.getCertificate(ALIAS).getPublicKey();
        ECKey jwk = new ECKey.Builder(Curve.P_256, publicKey).build();
        try (OutputStream output = context.openFileOutput("public-key.json", Context.MODE_PRIVATE)) {
            output.write(jwk.toJSONString().getBytes(StandardCharsets.UTF_8));
        }
    }
}
