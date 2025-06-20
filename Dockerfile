FROM ubuntu:22.04

# Install build tools and dependencies
RUN apt-get update && apt-get install -y \
    clang-14 \
    cmake \
    make \
    git \
    gperf \
    wget \
    perl \
    build-essential \
    libstdc++-11-dev \
    && rm -rf /var/lib/apt/lists/*

# Set clang-14 as default compiler
ENV CC=/usr/bin/clang-14
ENV CXX=/usr/bin/clang++-14

# Build zlib statically
RUN wget https://zlib.net/fossils/zlib-1.3.tar.gz \
    && tar -xzf zlib-1.3.tar.gz \
    && cd zlib-1.3 \
    && ./configure --static --prefix=/usr/local \
    && make -j$(nproc) \
    && make install \
    && cd .. \
    && rm -rf zlib-1.3 zlib-1.3.tar.gz

# Debug: Verify zlib
RUN ls -l /usr/local/lib/libz.a || echo "zlib library missing"

# Build openssl statically
RUN wget https://github.com/openssl/openssl/releases/download/openssl-3.4.1/openssl-3.4.1.tar.gz \
    && tar -xzf openssl-3.4.1.tar.gz \
    && cd openssl-3.4.1 \
    && ./config no-shared --prefix=/usr/local --openssldir=/usr/local/ssl \
    && make -j$(nproc) \
    && make install_sw install_ssldirs \
    && cd .. \
    && rm -rf openssl-3.4.1 openssl-3.4.1.tar.gz

# Debug: Search for OpenSSL libraries
RUN echo "Listing /usr/local/lib:" \
    && ls -l /usr/local/lib/ || echo "No /usr/local/lib directory" \
    && echo "Listing /usr/local/lib64:" \
    && ls -l /usr/local/lib64/ || echo "No /usr/local/lib64 directory" \
    && echo "Listing /usr/lib:" \
    && ls -l /usr/lib/ || echo "No /usr/lib directory" \
    && echo "Searching for libssl.a and libcrypto.a:" \
    && find /usr -name "libssl.a" -o -name "libcrypto.a" || echo "No OpenSSL static libraries found" \
    && echo "Checking OpenSSL version:" \
    && /usr/local/bin/openssl version || echo "OpenSSL binary not found"

# Debug: Verify OpenSSL libraries in expected location
RUN ls -l /usr/local/lib64/libssl.a /usr/local/lib64/libcrypto.a || echo "OpenSSL libraries missing in /usr/local/lib64"

# Debug: Test OpenSSL static linking
RUN echo 'int main() { return 0; }' > test.c \
    && clang-14 -static -o test test.c -L/usr/local/lib64 -lssl -lcrypto -lz \
    && rm test.c test || echo "OpenSSL static linking test failed"

# Clone telegram-bot-api and build statically
ARG TELEGRAM_API_REF=master
RUN git clone --recursive https://github.com/tdlib/telegram-bot-api.git /telegram-bot-api \
    && cd /telegram-bot-api \
    && git checkout ${TELEGRAM_API_REF} \
    && sed -i 's|td/db/KeyValueSyncInterface.h|tddb/td/db/KeyValueSyncInterface.h|' telegram-bot-api/ClientParameters.h \
    && rm -rf build \
    && mkdir build \
    && cd build \
    && cmake -DCMAKE_BUILD_TYPE=Release \
             -DCMAKE_INSTALL_PREFIX:PATH=.. \
             -DBUILD_SHARED_LIBS=OFF \
             -DCMAKE_EXE_LINKER_FLAGS="-static -L/usr/local/lib64 -lstdc++" \
             -DCMAKE_CXX_FLAGS="-static -I/telegram-bot-api/td" \
             -DOPENSSL_USE_STATIC_LIBS=ON \
             -DCMAKE_FIND_LIBRARY_SUFFIXES=".a" \
             -DOPENSSL_ROOT_DIR=/usr/local \
             -DOPENSSL_INCLUDE_DIR=/usr/local/include \
             -DOPENSSL_LIBRARIES="/usr/local/lib64/libssl.a;/usr/local/lib64/libcrypto.a" \
             -DOPENSSL_CRYPTO_LIBRARY=/usr/local/lib64/libcrypto.a \
             -DOPENSSL_SSL_LIBRARY=/usr/local/lib64/libssl.a \
             -DZLIB_ROOT=/usr/local \
             -DZLIB_INCLUDE_DIR=/usr/local/include \
             -DZLIB_LIBRARY=/usr/local/lib/libz.a \
             .. \
    && cmake --build . --target install -j$(nproc)