FROM nginx:alpine
COPY index.html privacy.html compare.html terms.html legal.html key.html thanks.html visit.js sitemap.xml robots.txt app-icon.png app-screenshot.png cleanup.png og-image.png appcast.xml SwitchForClaude*.dmg /usr/share/nginx/html/
COPY default.conf.template /etc/nginx/templates/default.conf.template
# Only these two are filled in; nginx's own $variables stay as they are.
ENV NGINX_ENVSUBST_FILTER="^(BUY_URL|KEY_API)$"
EXPOSE 8080
