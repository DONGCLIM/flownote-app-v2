"""시안 로고(`fnLogo`)를 전 플랫폼 앱 아이콘으로 일괄 생성한다.

원본: assets/icon/app_icon.png (1254x1254, 시안 __bundler/manifest 에서 추출)

생성 대상
  - android  mipmap-{mdpi..xxxhdpi} / ic_launcher, ic_launcher_round, ic_launcher_foreground
  - android  mipmap-{mdpi..xxxhdpi} / launch_image  (부팅 스플래시)
  - ios      AppIcon.appiconset/*.png  (알파 제거 — ITMS-90717)
  - ios      LaunchImage.imageset/LaunchImage{,@2x,@3x}.png  (부팅 스플래시)
  - web      icons/Icon-{192,512}.png, Icon-maskable-{192,512}.png, favicon.png

🔴 부팅 스플래시도 여기서 만든다 (Build 26 부터)

  이전에는 `launch_image.png` 가 손으로 넣은 파일이어서 앱 아이콘과
  **그림이 달랐다.** 부팅 순간에는 주황 튤립이 보이고, Flutter 가 첫
  프레임을 그리는 순간 분홍 장미로 바뀌었다. 켜자마자 브랜드가 두 번
  바뀌는 셈이었다. iOS 쪽은 아예 1x1 빈 이미지였다.
  아이콘과 스플래시는 같은 원본에서 같이 만들어야 어긋나지 않는다.

사용: python3 tool/gen_icons.py
"""

import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "icon", "app_icon.png")

# 시안 로고 배경의 연한 로즈. iOS/파비콘 알파 평탄화에 쓴다.
BG = (253, 240, 240)

# 부팅 스플래시 배경.
#
# 🔴 세 곳이 정확히 같아야 한다. 하나라도 다르면 부팅 → 앱 전환 순간에
#    배경이 번쩍인다.
#      1) 이 값                                        (스플래시 비트맵)
#      2) android/.../drawable*/launch_background.xml  (bitmap 아래 색)
#      3) lib/main.dart 의 Color(0xFFFFFCFA)           (Flutter 첫 화면)
#    예전에는 XML 이 #FFF8F5, Flutter 가 #FFFCFA 로 서로 달랐다.
SPLASH_BG = (255, 252, 250)  # #FFFCFA


def load() -> Image.Image:
    im = Image.open(SRC).convert("RGBA")
    # 정사각 보정
    if im.width != im.height:
        s = min(im.width, im.height)
        left = (im.width - s) // 2
        top = (im.height - s) // 2
        im = im.crop((left, top, left + s, top + s))
    return im


def resize(im: Image.Image, size: int) -> Image.Image:
    return im.resize((size, size), Image.LANCZOS)


def flatten(im: Image.Image) -> Image.Image:
    """알파 채널 제거. iOS 앱 아이콘은 알파가 있으면 업로드가 거부된다."""
    bg = Image.new("RGB", im.size, BG)
    bg.paste(im, mask=im.split()[3])
    return bg


def rounded(im: Image.Image, radius_ratio: float = 0.5) -> Image.Image:
    """원형/라운드 마스크 적용 (ic_launcher_round 용)."""
    mask = Image.new("L", im.size, 0)
    d = ImageDraw.Draw(mask)
    r = int(im.width * radius_ratio)
    d.rounded_rectangle((0, 0, im.width - 1, im.height - 1), radius=r, fill=255)
    out = im.copy()
    out.putalpha(mask)
    return out


def padded(im: Image.Image, size: int, scale: float) -> Image.Image:
    """adaptive icon foreground / maskable 처럼 안전영역이 필요한 경우.

    바깥이 잘려도 로고가 살아남도록 축소해서 가운데 배치한다.
    """
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    inner = resize(im, int(size * scale))
    off = (size - inner.width) // 2
    canvas.paste(inner, (off, off), inner)
    return canvas


def rounded_alpha(im: Image.Image, radius_ratio: float) -> Image.Image:
    """둥근 사각형 마스크. 앱 안 로고(`r22` on `84px`)와 같은 곡률을 쓴다."""
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, im.width - 1, im.height - 1),
        radius=int(im.width * radius_ratio),
        fill=255,
    )
    out = im.copy()
    out.putalpha(mask)
    return out


def splash(width: int, height: int) -> Image.Image:
    """부팅 스플래시 한 장을 만든다.

    앱 안 스플래시 화면(`splash_ds_screen.dart`)과 같은 모습으로 맞춘다.
      - 로고: 둥근 사각형(84px 기준 r22 → 비율 22/84)
      - 그림자: rgba(238,118,134,.22), blur 18, y+6
      - 배경: SPLASH_BG

    🔴 글자를 넣지 않는다.
       예전 스플래시에는 "FlowNote" 가 그려져 있었다. 비트맵에 박힌 글자는
       폰트도 자간도 앱 안과 다르고, 기기 언어나 다크모드에 반응하지 못한다.
       Flutter 가 첫 프레임을 그리면 같은 자리에 앱 폰트로 다시 그리므로
       글자가 미묘하게 튀어 보였다. 로고만 두면 그 전환이 보이지 않는다.
    """
    src = load()
    canvas = Image.new("RGB", (width, height), SPLASH_BG)

    # 로고 크기 — 화면 너비의 30%. 기기가 커도 작아도 비슷하게 보인다.
    # 짧은 변을 기준으로 잡아야 가로 모드에서 화면을 넘지 않는다.
    box = max(72, int(min(width, height) * 0.30))
    logo = rounded_alpha(resize(src, box), 22 / 84)

    # 그림자를 로고보다 먼저 깔아야 아래에 놓인다. 앱 안 값과 동일:
    #   color rgba(238,118,134,.22) · blur 18 · offset (0, 6)
    # 원본 84px 기준이므로 실제 로고 크기에 비례해서 키운다.
    k = box / 84.0
    blur = max(1.0, 18 * k)
    dy = int(round(6 * k))
    pad = int(blur * 3)

    shadow = Image.new("RGBA", (box + pad * 2, box + pad * 2), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (pad, pad, pad + box - 1, pad + box - 1),
        radius=int(box * 22 / 84),
        fill=(238, 118, 134, 56),  # .22 * 255 ≈ 56
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))

    # 로고를 화면 정중앙에 둔다. Flutter 첫 화면(`main.dart`)도 Center 라서
    # 여기서 어긋나면 전환 순간 로고가 튄다.
    cx = (width - box) // 2
    cy = (height - box) // 2

    canvas.paste(shadow, (cx - pad, cy - pad + dy), shadow)
    canvas.paste(logo, (cx, cy), logo)
    return canvas


def save(im: Image.Image, path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path, "PNG", optimize=True)
    print(f"  {os.path.relpath(path, ROOT)}  {im.size[0]}x{im.size[1]} {im.mode}")


def main() -> None:
    src = load()
    print(f"source {os.path.relpath(SRC, ROOT)} {src.size[0]}x{src.size[1]}")

    # ── Android ──────────────────────────────────────────────
    print("android:")
    android = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for dpi, size in android.items():
        base = os.path.join(ROOT, "android/app/src/main/res", f"mipmap-{dpi}")
        icon = resize(src, size)
        save(icon, os.path.join(base, "ic_launcher.png"))
        save(rounded(icon), os.path.join(base, "ic_launcher_round.png"))
        # adaptive foreground: 마스크로 잘리므로 여유를 둔다
        save(padded(src, size, 0.72), os.path.join(base, "ic_launcher_foreground.png"))

    # ── iOS (알파 없음) ───────────────────────────────────────
    print("ios:")
    ios = [
        ("20x20@1x", 20), ("20x20@2x", 40), ("20x20@3x", 60),
        ("29x29@1x", 29), ("29x29@2x", 58), ("29x29@3x", 87),
        ("40x40@1x", 40), ("40x40@2x", 80), ("40x40@3x", 120),
        ("60x60@2x", 120), ("60x60@3x", 180),
        ("76x76@1x", 76), ("76x76@2x", 152),
        ("83.5x83.5@2x", 167),
        ("1024x1024@1x", 1024),
    ]
    ios_dir = os.path.join(ROOT, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
    for name, size in ios:
        save(flatten(resize(src, size)), os.path.join(ios_dir, f"Icon-App-{name}.png"))

    # ── Web ──────────────────────────────────────────────────
    print("web:")
    web_dir = os.path.join(ROOT, "web/icons")
    for size in (192, 512):
        save(resize(src, size), os.path.join(web_dir, f"Icon-{size}.png"))
        # maskable: 원형으로 잘려도 로고가 온전하도록 축소 + 배경 채움
        m = Image.new("RGBA", (size, size), BG + (255,))
        inner = resize(src, int(size * 0.78))
        off = (size - inner.width) // 2
        m.paste(inner, (off, off), inner)
        save(m, os.path.join(web_dir, f"Icon-maskable-{size}.png"))
    save(flatten(resize(src, 64)), os.path.join(ROOT, "web/favicon.png"))

    # ── 부팅 스플래시 ─────────────────────────────────────────
    # 아이콘과 **같은 원본에서 같이** 만든다. 따로 관리하면 또 어긋난다.
    print("splash (android):")
    # 밀도별 기준 해상도. Android 는 화면에 맞춰 늘리지 않고 gravity=center
    # 로 원본 크기 그대로 놓기 때문에, 각 밀도의 대표 해상도로 만들어야
    # 로고가 흐려지지 않는다.
    for dpi, (w, h) in {
        "mdpi": (320, 480),
        "hdpi": (480, 800),
        "xhdpi": (720, 1280),
        "xxhdpi": (1080, 1920),
        "xxxhdpi": (1440, 2560),
    }.items():
        base = os.path.join(ROOT, "android/app/src/main/res", f"mipmap-{dpi}")
        save(splash(w, h), os.path.join(base, "launch_image.png"))

    print("splash (ios):")
    # iOS 는 LaunchImage 를 화면 크기에 맞춰 늘린다(`scaleAspectFill` 유사).
    # 그래서 정사각으로 만들어 어느 비율에서도 로고가 가운데 남게 한다.
    # 예전에는 세 장 모두 **1x1 빈 이미지**여서 스플래시가 사실상 없었다.
    ios_launch = os.path.join(ROOT, "ios/Runner/Assets.xcassets/LaunchImage.imageset")
    for name, size in (("LaunchImage", 640), ("LaunchImage@2x", 1280), ("LaunchImage@3x", 1920)):
        save(splash(size, size), os.path.join(ios_launch, f"{name}.png"))


if __name__ == "__main__":
    main()
