package edu.secure.assign.web;

import edu.secure.assign.domain.Customer;
import edu.secure.assign.domain.CustomerView;
import edu.secure.assign.mapper.CustomerMapper;
import edu.secure.assign.security.AesCrypto;
import edu.secure.assign.security.MaskingUtil;
import jakarta.servlet.http.HttpSession;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api")
public class CustomerController {

    private static final Logger log = LoggerFactory.getLogger(CustomerController.class);

    /** 초기 데이터(C001~C003)처럼 암호화되지 않은 주민번호 형식 */
    private static final String PLAIN_RRN = "\\d{6}-\\d{7}";

    private final CustomerMapper customerMapper;
    private final AesCrypto crypto;

    public CustomerController(CustomerMapper customerMapper, AesCrypto crypto) {
        this.customerMapper = customerMapper;
        this.crypto = crypto;
    }

    @GetMapping("/customers/{customerId}")
    public CustomerView customer(@PathVariable String customerId, HttpSession session) {
        String me = LoginController.requireCustomer(session);
        if (!me.equals(customerId)) {                              // 본인 정보만 조회
            throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        }
        Customer c = customerMapper.findById(customerId);
        if (c == null) {                                           // 세션은 있는데 고객이 없는 경우
            throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        }
        // 가입 고객은 암호문으로 저장 → 복호화한 뒤 마스킹 (초기 데이터는 평문이라 그대로)
        String rrn = c.getRrn().matches(PLAIN_RRN) ? c.getRrn() : crypto.decrypt(c.getRrn());
        log.info("고객 조회: customerId={}", customerId);           // 식별자만 기록
        return new CustomerView(c.getCustomerId(), c.getCustomerName(),
                MaskingUtil.maskRrn(rrn), MaskingUtil.maskPhone(c.getPhone()));
    }
}