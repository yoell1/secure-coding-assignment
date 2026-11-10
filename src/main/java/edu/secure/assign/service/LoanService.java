package edu.secure.assign.service;

import edu.secure.assign.domain.Loan;
import edu.secure.assign.mapper.LoanMapper;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.List;
import java.util.Set;

@Service
public class LoanService {

    /** ORDER BY 허용 목록 */
    private static final Set<String> ALLOWED_SORT = Set.of("loan_id", "balance");

    private final LoanMapper loanMapper;

    public LoanService(LoanMapper loanMapper) {
        this.loanMapper = loanMapper;
    }

    /** 정렬 기준(sortBy)으로 대출 목록 조회 — 허용 목록에 있는 값만 통과 */
    public List<Loan> findSorted(String customerId, String sortBy) {
        if (!ALLOWED_SORT.contains(sortBy)) {
            throw new IllegalArgumentException("허용되지 않은 정렬 기준입니다.");
        }
        return loanMapper.findSorted(customerId, sortBy);
    }

    /** 대출 상환. 소유자·잔액 확인과 차감을 조건부 UPDATE 한 문장으로 처리 */
    public boolean repay(long loanId, String customerId, long amount) {
        if (amount <= 0) {
            throw new IllegalArgumentException("상환 금액은 0보다 커야 합니다.");
        }
        return loanMapper.repayConditional(loanId, customerId, amount) == 1;
    }

    /** 월 이자 = 원금 × 연이율 ÷ 12 (BigDecimal, 원 단위 HALF_UP 반올림) */
    public long monthlyInterest(long principal, String annualRate) {
        BigDecimal rate = new BigDecimal(annualRate);
        if (principal <= 0) {
            throw new IllegalArgumentException("원금은 0보다 커야 합니다.");
        }
        if (rate.signum() < 0 || rate.compareTo(BigDecimal.ONE) > 0) {
            throw new IllegalArgumentException("금리는 0 이상 1 이하여야 합니다.");
        }
        return BigDecimal.valueOf(principal)
                .multiply(rate)
                .divide(BigDecimal.valueOf(12), 0, RoundingMode.HALF_UP)
                .longValueExact();
    }
}