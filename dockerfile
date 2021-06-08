# nwnsc compiler
FROM nwneetools/nwnsc:latest as nwnsc
# nim image
FROM nimlang/nim:alpine as nasher
COPY --from=nwnsc usr/local/bin/nwnsc usr/local/bin/nwnsc
COPY --from=nwnsc /nwn /nwn
RUN apk add --no-cache bash
ARG NASHER_VERSION="0.13.0"
ENV PATH="/root/.nimble/bin:$PATH"
RUN nimble install nasher@#${NASHER_VERSION} -y
RUN nasher config --nssFlags:"-n /nwn/data -o" \
    && nasher config --installDir:"/nasher/install" \
    && nasher config --userName:"nasher" \
    && nasher config --nssCompiler:"/usr/local/bin/nwnsc"
WORKDIR /nasher
RUN bash -c "mkdir -pv /nasher/install/{erf,hak,modules,tlk}"
ENTRYPOINT [ "nasher" ]
CMD [ "--help" ]
