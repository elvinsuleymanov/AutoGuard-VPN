from typing import Any
from fastapi import FastAPI, Security, HTTPException
from pydantic import BaseModel, field_validator
from helpers import (
    verify,
    is_valid_wg_pubkey,
    allocate_ip,
    write_peer_conf,
    generate_client_config,
)

app = FastAPI()


class PeerRequest(BaseModel):
    public_key: str

    @field_validator("public_key")
    @classmethod
    def validate_public_key(cls, v: str) -> str:
        if not is_valid_wg_pubkey(v):
            raise ValueError("Invalid WireGuard public key")
        return v


@app.get("/health")
def health_check() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/addnewpeer", dependencies=[Security(verify)])
def add_peer(peer: PeerRequest) -> Any:
    try:
        ip = allocate_ip()
    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e))

    try:
        write_peer_conf(peer.public_key, ip)
    except FileExistsError:
        raise HTTPException(status_code=409, detail="Peer already registered")

    try:
        config = generate_client_config(ip)
    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e))

    return {"status": "ok", "ip": ip, "config": config}
