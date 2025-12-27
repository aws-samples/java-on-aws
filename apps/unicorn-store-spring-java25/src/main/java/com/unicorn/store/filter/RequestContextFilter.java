package com.unicorn.store.filter;

import com.unicorn.store.context.RequestContext;
import jakarta.servlet.Filter;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletRequest;
import jakarta.servlet.ServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.util.UUID;

// Binds request ID to ScopedValue for the duration of each HTTP request
@Component("scopedValueRequestContextFilter")
@Order(Ordered.HIGHEST_PRECEDENCE)
public class RequestContextFilter implements Filter {

    private static final Logger logger = LoggerFactory.getLogger(RequestContextFilter.class);

    @Override
    public void doFilter(ServletRequest request, ServletResponse response,
                         FilterChain chain) throws IOException, ServletException {
        String requestId = UUID.randomUUID().toString();

        // Java 25 Scoped Values (JEP 506) - value auto-cleaned when run() completes
        try {
            ScopedValue.where(RequestContext.REQUEST_ID, requestId).run(() -> {
                logger.debug("[{}] Request started", requestId);
                try {
                    chain.doFilter(request, response);
                } catch (IOException | ServletException e) {
                    throw new RuntimeException(e);
                } finally {
                    logger.debug("[{}] Request completed", requestId);
                }
            });
        } catch (RuntimeException e) {
            // Unwrap checked exceptions that were wrapped in RuntimeException
            if (e.getCause() instanceof IOException ioException) {
                throw ioException;
            }
            if (e.getCause() instanceof ServletException servletException) {
                throw servletException;
            }
            throw e;
        }
    }
}
