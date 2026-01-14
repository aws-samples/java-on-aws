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

/**
 * Binds request ID to ThreadLocal for the duration of each HTTP request.
 */
@Component("unicornRequestContextFilter")
@Order(Ordered.HIGHEST_PRECEDENCE)
public class RequestContextFilter implements Filter {

    private static final Logger logger = LoggerFactory.getLogger(RequestContextFilter.class);

    @Override
    public void doFilter(ServletRequest request, ServletResponse response,
                         FilterChain chain) throws IOException, ServletException {
        String requestId = UUID.randomUUID().toString();

        try {
            RequestContext.set(requestId);
            logger.debug("[{}] Request started", requestId);
            chain.doFilter(request, response);
        } finally {
            logger.debug("[{}] Request completed", requestId);
            RequestContext.clear();
        }
    }
}
