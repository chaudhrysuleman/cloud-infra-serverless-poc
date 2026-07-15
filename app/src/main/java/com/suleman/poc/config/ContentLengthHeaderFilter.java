package com.suleman.poc.config;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpServletResponseWrapper;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

@Component
public class ContentLengthHeaderFilter extends OncePerRequestFilter {

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {

        HttpServletResponseWrapper wrapper = new HttpServletResponseWrapper(response) {
            @Override
            public void setHeader(String name, String value) {
                if (!"Content-Length".equalsIgnoreCase(name)) {
                    super.setHeader(name, value);
                }
            }

            @Override
            public void addHeader(String name, String value) {
                if (!"Content-Length".equalsIgnoreCase(name)) {
                    super.addHeader(name, value);
                }
            }

            @Override
            public void setContentLength(int len) {
                // Do nothing to strip Content-Length
            }

            @Override
            public void setContentLengthLong(long len) {
                // Do nothing to strip Content-Length
            }
        };

        filterChain.doFilter(request, wrapper);
    }
}
