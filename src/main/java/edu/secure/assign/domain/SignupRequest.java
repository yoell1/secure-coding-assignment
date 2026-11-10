package edu.secure.assign.domain;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/** 회원가입 요청 본문 — 필드마다 허용 형식을 정해 두고, 맞지 않으면 거부한다 */
public record SignupRequest(

        @NotBlank
        @Pattern(regexp = "^[A-Za-z0-9]{1,10}$")          // 영문·숫자만, 1~10자
        String customerId,

        @NotBlank
        @Pattern(regexp = "^[가-힣A-Za-z ]{1,50}$")        // 한글·영문·공백만, 1~50자
        String customerName,

        @NotBlank
        @Pattern(regexp = "^\\d{6}-\\d{7}$")              // 숫자6-숫자7
        String rrn,

        @NotBlank
        @Pattern(regexp = "^01\\d-\\d{3,4}-\\d{4}$")      // 01x-xxxx-xxxx
        String phone,

        @NotBlank
        @Size(min = 8, max = 64)                          // 8~64자
        String password) {

    /** record 기본 toString()은 모든 칸을 출력 → 실수로 로그에 찍혀도 ID만 나가게 */
    @Override
    public String toString() {
        return "SignupRequest[customerId=" + customerId + "]";
    }
}