FROM rust:latest

ENV RFS_API_KEY=passwd

WORKDIR /rfs

COPY Cargo.toml Cargo.lock ./
COPY src ./src
RUN cargo build --release

RUN apt update -y
RUN apt install -y restic 
RUN restic self-update

EXPOSE 8000
CMD ["cargo", "run", "--release"]
