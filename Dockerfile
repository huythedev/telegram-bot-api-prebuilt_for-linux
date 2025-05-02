FROM alpine:3.18

# Install build tools and dependencies
RUN apk add --no-cache \
    clang \
    llvm \
    cmake \
    make \
    git \
    gperf \
    wget \
    perl \
    musl-dev \
    linux-headers

# Set clang as default compiler
ENV CC=/usr/bin/clang
ENV CXX=/usr/bin/clang++

# Build zlib statically
RUN wget https://zlib.net/fossils/zlib-1.3.tar.gz \
    && tar -xzf zlib-1.3.tar.gz \
    && cd zlib-1.3 \
    && ./configure --static --prefix=/usr/local \
    && make -j$(nproc) \
    && make install \
    && cd .. \
    && rm -rf zlib-1.3 zlib-1.3.tar.gz

# Build openssl statically
RUN wget https://github.com/openssl/openssl/releases/download/openssl-3.4.1/openssl-3.4.1.tar.gz \
    && tar -xzf openssl-3.4.1.tar.gz \
    && cd openssl-3.4.1 \
    && ./config no-shared --prefix=/usr/local --openssldir=/usr/local/ssl \
    && make -j$(nproc) \
    && make install \
    && cd .. \
    && rm -rf openssl-3.4.1 openssl-3.4.1.tar.gz

# Clone telegram-bot-api and build statically
ARG TELEGRAM_API_REF=master
RUN git clone --recursive https://github.com/tdlib/telegram-bot-api.git /telegram-bot-api \
    && cd /telegram-bot-api \
    && git checkout ${TELEGRAM_API_REF} \
    && sed -i 's|td/db/KeyValueSyncInterface.h|tddb/td/db/KeyValueSyncInterface.h|' telegram-bot-api/ClientParameters.h \
    && mkdir build \
    && cd build \
    && CXXFLAGS="-static -I/telegram-bot-api/telegram-bot-api/td" \
       LDFLAGS="-static -L/usr/local/lib" \
       CC=/usr/bin/clang \
       CXX=/usr/bin/clang++ \
       cmake -DCMAKE_BUILD_TYPE=Release \
             -DCMAKE_INSTALL_PREFIX:PATH=.. \
             -DBUILD_SHARED_LIBS=OFF \
             -DCMAKE_EXE_LINKER_FLAGS="-static -L/usr/local/lib" \
             -DOPENSSL_USE_STATIC_LIBS=ON \
             -DCMAKE_FIND_LIBRARY_SUFFIXES=".a" \
             -DOPENSSL_ROOT_DIR=/usr/local \
             -DOPENSSL_INCLUDE_DIR=/usr/local/include \
             -DOPENSSL_LIBRARIES="/usr/local/lib/libssl.a;/usr/local/lib/libcrypto.a" \
             -DOPENSSL_CRYPTO_LIBRARY=/usr/local/lib/libcrypto.a \
             -DOPENSSL_SSL_LIBRARY=/usr/local/lib/libssl.a \
             -DZLIB_ROOT=/usr/local \
             -DZLIB_INCLUDE_DIR=/usr/local/include \
             -DZLIB_LIBRARY=/usr/local/lib/libz.a \
             .. \
    && cmake --build . --target install -j$(nproc)