package edu.secure.assign.web;

import edu.secure.assign.service.LoanService;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.HexFormat;

/** 화면(JSP) 컨트롤러 */
@Controller
public class PageController {

    private static final String CSRF_KEY = "csrfToken";
    private final SecureRandom random = new SecureRandom();
    private final LoanService loanService;

    public PageController(LoanService loanService) {
        this.loanService = loanService;
    }

    @GetMapping("/login-page")
    public String loginPage() {
        return "login";
    }

    @GetMapping("/search")
    public String search(@RequestParam(defaultValue = "") String q, Model model) {
        model.addAttribute("q", q);
        return "search";
    }

    /** 상환 폼: 다른 사이트 안에 넣지 못하게 막고, 무작위 CSRF 토큰을 세션과 폼에 넣는다 */
    @GetMapping("/repay-form")
    public String repayForm(Model model, HttpSession session, HttpServletResponse response) {
        response.setHeader("X-Frame-Options", "DENY");                          // 클릭재킹 방지
        response.setHeader("Content-Security-Policy", "frame-ancestors 'none'"); // 같은 뜻의 최신 방식
        byte[] bytes = new byte[32];
        random.nextBytes(bytes);
        String token = HexFormat.of().formatHex(bytes);
        session.setAttribute(CSRF_KEY, token);
        model.addAttribute("csrf", token);
        return "repay-form";
    }

    /** 상환 처리: 폼에서 온 토큰과 세션 토큰이 다르면 403. 맞으면 토큰은 한 번만 쓰고 폐기 */
    @PostMapping("/repay-form")
    @ResponseBody
    public String repay(@RequestParam long loanId, @RequestParam long amount,
                        @RequestParam(name = "_csrf", required = false) String csrf, HttpSession session) {
        String me = LoginController.requireCustomer(session);
        Object expected = session.getAttribute(CSRF_KEY);
        if (expected == null || csrf == null || !MessageDigest.isEqual(
                expected.toString().getBytes(StandardCharsets.UTF_8), csrf.getBytes(StandardCharsets.UTF_8))) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN);
        }
        session.removeAttribute(CSRF_KEY);                       // 같은 토큰으로 다시 보내지 못하게 (재사용 방지)
        return "상환 처리: " + loanService.repay(loanId, me, amount);
    }
}