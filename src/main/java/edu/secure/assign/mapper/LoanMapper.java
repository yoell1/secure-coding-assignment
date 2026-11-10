package edu.secure.assign.mapper;

import edu.secure.assign.domain.Loan;
import org.apache.ibatis.annotations.Param;

import java.util.List;

public interface LoanMapper {

    List<Loan> findByCustomer(@Param("customerId") String customerId);

    List<Loan> findSorted(@Param("customerId") String customerId, @Param("sortBy") String sortBy);

    Loan findById(@Param("loanId") long loanId, @Param("customerId") String customerId);

    /** 소유자·잔액 확인과 차감을 한 문장으로 처리. 반환값 = 바뀐 행 수(0 또는 1) */
    int repayConditional(@Param("loanId") long loanId,
                         @Param("customerId") String customerId,
                         @Param("amount") long amount);
}