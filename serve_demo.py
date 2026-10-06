"""데모용 정적 서버 — 브라우저 캐시를 완전히 차단한다.

Flutter web 빌드는 기본적으로 service worker + 강한 캐시를 사용해
새 빌드를 올려도 구버전 화면이 계속 보이는 일이 잦다.
데모 확인용이므로 모든 응답에 no-store 를 붙인다.
"""

import functools
import http.server
import os
import socketserver

# 미리보기 패널이 붙는 표준 포트. 다른 포트로 옮기면 미리보기가 끊긴다.
PORT = int(os.environ.get("PORT", "8080"))
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build", "web")


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    # Flutter web 은 .wasm / .mjs 를 쓰는데 파이썬 기본 표에는 없다.
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".mjs": "text/javascript",
        ".js": "text/javascript",
        ".json": "application/json",
        ".symbols": "text/plain",
    }

    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def log_message(self, fmt, *args):  # 조용히
        pass


class Server(socketserver.ThreadingTCPServer):
    """Flutter web 은 파일을 수십 개 동시에 받는다. 단일 스레드면 로딩이 느리다."""

    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    handler = functools.partial(NoCacheHandler, directory=ROOT)
    with Server(("0.0.0.0", PORT), handler) as httpd:
        print(f"serving {ROOT} on :{PORT} (no-store)")
        httpd.serve_forever()
