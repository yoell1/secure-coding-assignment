package edu.secure.assign.security;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.Base64;

/** 주민등록번호 등 복호화가 필요한 데이터의 대칭 암호화 (AES-GCM, 키는 환경 변수로만 주입) */
@Component
public class AesCrypto {

    private static final int IV_BYTES = 12;      // GCM 권장 IV 길이
    private static final int TAG_BITS = 128;     // 위·변조 검사용 태그 길이

    private final SecureRandom random = new SecureRandom();
    private final String base64Key;

    public AesCrypto(@Value("${assign.aes-key}") String base64Key) {
        this.base64Key = base64Key;
    }

    public String encrypt(String plain) {
        try {
            byte[] iv = new byte[IV_BYTES];
            random.nextBytes(iv);                                  // 매번 새로운 IV
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, key(), new GCMParameterSpec(TAG_BITS, iv));
            byte[] enc = cipher.doFinal(plain.getBytes(StandardCharsets.UTF_8));
            // 저장 형식: IV + 암호문 (복호화할 때 IV가 필요하므로 앞에 붙여 둔다)
            byte[] out = ByteBuffer.allocate(iv.length + enc.length).put(iv).put(enc).array();
            return Base64.getEncoder().encodeToString(out);
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("암호화 실패", e);
        }
    }

    public String decrypt(String token) {
        try {
            ByteBuffer buf = ByteBuffer.wrap(Base64.getDecoder().decode(token));
            byte[] iv = new byte[IV_BYTES];
            buf.get(iv);                                           // 앞 12바이트 = IV
            byte[] enc = new byte[buf.remaining()];
            buf.get(enc);                                          // 나머지 = 암호문
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(TAG_BITS, iv));
            return new String(cipher.doFinal(enc), StandardCharsets.UTF_8);
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("복호화 실패", e);
        }
    }

    /** 주입받은 키(Base64)를 꺼낸다. 비어 있으면 동작하지 않는다 */
    private SecretKeySpec key() {
        if (base64Key == null || base64Key.isBlank()) {
            throw new IllegalStateException("ASSIGN_AES_KEY 환경 변수가 설정되지 않았습니다.");
        }
        return new SecretKeySpec(Base64.getDecoder().decode(base64Key), "AES");
    }
}