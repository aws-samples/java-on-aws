package com.unicorn.store.otel;

import jakarta.servlet.*;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.web.util.ContentCachingResponseWrapper;

import java.io.IOException;

public class ApplicationFilter implements Filter {

    private final MetricEmitter metricEmitter;

    public ApplicationFilter(MetricEmitter metricEmitter) {
        this.metricEmitter = metricEmitter;
    }

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain) throws IOException, ServletException {

        long requestStartTime = System.currentTimeMillis();

        ContentCachingResponseWrapper responseWrapper = new ContentCachingResponseWrapper((HttpServletResponse) response);

        chain.doFilter(request, responseWrapper);

        int loadSize = responseWrapper.getContentSize();

        responseWrapper.copyBodyToResponse();

        String statusCode = String.valueOf(((HttpServletResponse)response).getStatus());

        metricEmitter.emitReturnTimeMetric(
                System.currentTimeMillis() - requestStartTime, ((HttpServletRequest)request).getServletPath(), statusCode);


        metricEmitter.emitBytesSentMetric(loadSize, ((HttpServletRequest)request).getServletPath(), statusCode);
    }
}

