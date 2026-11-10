package edu.secure.assign.domain;

/** 고객 조회 응답 전용 객체. 필요한 항목만, 마스킹해서 담는다. */
public record CustomerView(
        String customerId,
        String customerName,
        String rrnMasked,
        String phoneMasked) {
}