package edu.secure.assign.web;

import edu.secure.assign.domain.Loan;
import edu.secure.assign.mapper.LoanMapper;
import edu.secure.assign.service.LoanService;
import jakarta.servlet.http.HttpSession;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api")
public class LoanController {

    private final LoanMapper loanMapper;
    private final LoanService loanService;

    public LoanController(LoanMapper loanMapper, LoanService loanService) {
        this.loanMapper = loanMapper;
        this.loanService = loanService;
    }

    @GetMapping("/loans")
    public List<Loan> loans(@RequestParam String customerId, HttpSession session) {
        String me = LoginController.requireCustomer(session);
        if (!me.equals(customerId)) {                              // 본인 대출만 조회
            throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        }
        return loanMapper.findByCustomer(customerId);
    }

    @GetMapping("/loans/sorted")
    public List<Loan> sorted(@RequestParam String customerId, @RequestParam String sortBy, HttpSession session) {
        String me = LoginController.requireCustomer(session);
        if (!me.equals(customerId)) {                              // 본인 대출만 조회
            throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        }
        return loanService.findSorted(customerId, sortBy);
    }

    @GetMapping("/loans/{loanId}")
    public Loan loan(@PathVariable long loanId, HttpSession session) {
        String me = LoginController.requireCustomer(session);
        Loan loan = loanMapper.findById(loanId, me);
        if (loan == null) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        }
        return loan;
    }

    /** 상환 API: 다른 사이트의 폼이 보낼 수 없는 헤더를 요구해서 CSRF를 막는다 */
    @PostMapping("/loans/{loanId}/repay")
    public Map<String, Object> repay(@PathVariable long loanId, @RequestParam long amount,
                                     @RequestHeader(name = "X-Requested-With", required = false) String requestedWith,
                                     HttpSession session) {
        String me = LoginController.requireCustomer(session);
        if (!"XMLHttpRequest".equals(requestedWith)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN);
        }
        return Map.of("success", loanService.repay(loanId, me, amount));
    }

    @GetMapping("/interest")
    public Map<String, Object> interest(@RequestParam long principal, @RequestParam String rate) {
        return Map.of("monthlyInterest", loanService.monthlyInterest(principal, rate));
    }
}