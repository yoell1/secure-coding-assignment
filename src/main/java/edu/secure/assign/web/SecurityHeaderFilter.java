package edu.secure.assign.web;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

/** 모든 응답에 보안 헤더를 붙인다 (화면마다 넣으면 빠뜨리기 쉬워서 필터 한 곳에서 처리) */
@Component
public class SecurityHeaderFilter extends OncePerRequestFilter {

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        response.setHeader("X-Frame-Options", "DENY");                        // 다른 사이트의 iframe 금지 (옛 방식)
        response.setHeader("Content-Security-Policy", "frame-ancestors 'none'"); // 다른 사이트의 iframe 금지 (CSP)
        response.setHeader("X-Content-Type-Options", "nosniff");              // 브라우저가 파일 형식을 추측하지 않게
        response.setHeader("Referrer-Policy", "same-origin");                 // 다른 사이트로 주소가 새지 않게
        response.setHeader("Cache-Control", "no-store");                      // 개인정보 응답이 브라우저·프록시에 남지 않게
        chain.doFilter(request, response);
    }
}