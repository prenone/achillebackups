use salvo::prelude::*;
use serde::Deserialize;
use std::io::{self, Write};
use std::path::Path;
use std::process::Command;

pub const RESTIC_REPOS_PATH: &'static str = "/rfs_repos";
const API_KEY: &'static str = env!("RFS_API_KEY");

#[handler]
async fn root() -> &'static str {
    "ResticSecureForget"
}

#[derive(Deserialize)]
struct ForgetRequest {
    repo: String,
    passwd: String,
    keep_within: String,
    tag: String,
    dry_run: bool,
    api_key: String,
}

#[handler]
async fn forget(req: &mut Request, res: &mut Response) {
    let forget_request = req.parse_json::<ForgetRequest>().await;

    match forget_request {
        Ok(forget_request) => {
            if forget_request.api_key != API_KEY {
                res.status_code(StatusCode::UNAUTHORIZED);
                return;
            }

            tokio::spawn(async move {
                let mut forget_command = Command::new("restic");
                forget_command
                    .env("RESTIC_PASSWORD", forget_request.passwd)
                    .arg("forget")
                    .arg("-r")
                    .arg(Path::new(RESTIC_REPOS_PATH).join(forget_request.repo))
                    .arg("--keep-within")
                    .arg(forget_request.keep_within);

                if !forget_request.tag.is_empty() {
                    forget_command.arg("--tag").arg(forget_request.tag);
                }

                if forget_request.dry_run {
                    forget_command.arg("--dry-run");
                }

                forget_command.arg("--prune");

                let forget_output = forget_command.output().expect("Failed to execute command");

                io::stdout().write_all(&forget_output.stdout).unwrap();
                io::stderr().write_all(&forget_output.stderr).unwrap();
            });

            res.status_code(StatusCode::OK);
        }
        Err(_) => {
            res.status_code(StatusCode::BAD_REQUEST);
        }
    };
}

#[tokio::main]
async fn main() {
    let router = Router::new()
        .push(Router::with_path("/").get(root))
        .push(Router::with_path("/forget").post(forget));

    let acceptor = TcpListener::new("0.0.0.0:8000").bind().await;

    Server::new(acceptor).serve(router).await;
}
