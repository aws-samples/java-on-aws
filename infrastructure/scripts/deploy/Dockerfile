FROM nginx:alpine

# Create a simple HTML page
RUN echo '<html><body><h1>Hello World!</h1></body></html>' > /usr/share/nginx/html/index.html

# Configure nginx to listen on port 8080
RUN sed -i 's/listen\s*80;/listen 8080;/' /etc/nginx/conf.d/default.conf

# Expose port 8080
EXPOSE 8080

# Start Nginx
CMD ["nginx", "-g", "daemon off;"]