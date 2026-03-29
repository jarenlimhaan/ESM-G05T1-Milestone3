FROM php:8.2-apache

# Install system dependencies
RUN apt-get update && apt-get install -y \
    wget \
    unzip \
    libzip-dev \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libldap2-dev \
    libonig-dev \
    && rm -rf /var/lib/apt/lists/*

# Configure and install PHP extensions
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
    gd \
    mysqli \
    pdo \
    pdo_mysql \
    zip \
    ldap \
    mbstring \
    opcache

# Download and install osTicket (v1.18.1)
RUN cd /tmp \
    && wget -q https://github.com/osTicket/osTicket/releases/download/v1.18.1/osTicket-v1.18.1.zip \
    && mkdir -p /var/www/html \
    && unzip -q /tmp/osTicket-v1.18.1.zip -d /var/www/html \
    && mv /var/www/html/upload/* /var/www/html/ \
    && rmdir /var/www/html/upload \
    && cp /var/www/html/include/ost-sampleconfig.php /var/www/html/include/ost-config.php \
    && chmod 0666 /var/www/html/include/ost-config.php \
    && chown -R www-data:www-data /var/www/html \
    && rm /tmp/osTicket-v1.18.1.zip

# Configure Apache
RUN a2enmod rewrite \
    && sed -ri 's!/var/www/html!/var/www/html!g' /etc/apache2/sites-available/*.conf

# Production-safe PHP error handling for osTicket on PHP 8.2.
# Prevent deprecation notices from being sent in HTTP responses.
RUN { \
      echo 'display_errors=Off'; \
      echo 'log_errors=On'; \
      echo 'error_reporting=E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED & ~E_STRICT'; \
    } > /usr/local/etc/php/conf.d/99-osticket.ini

COPY docker/osticket/entrypoint.sh /usr/local/bin/osticket-entrypoint.sh
RUN chmod +x /usr/local/bin/osticket-entrypoint.sh

WORKDIR /var/www/html
EXPOSE 80
ENTRYPOINT ["/usr/local/bin/osticket-entrypoint.sh"]
