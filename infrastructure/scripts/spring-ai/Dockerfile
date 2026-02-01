FROM public.ecr.aws/docker/library/nginx:1.29.4

# Create a HTML page with timestamp using shell command directly in RUN
RUN echo '<html><body><h1>Hello World!</h1><p>Build timestamp: '$(date)'</p></body></html>' > /usr/share/nginx/html/index.html

# Configure nginx to listen on port 8080
RUN sed -i 's/listen\s*80;/listen 8080;/' /etc/nginx/conf.d/default.conf

# Expose port 8080
EXPOSE 8080

# Start Nginx
CMD ["nginx", "-g", "daemon off;"]
