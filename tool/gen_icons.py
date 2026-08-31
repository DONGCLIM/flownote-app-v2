"""확정 브랜드 자산을 전 플랫폼 앱 아이콘 / 스플래시로 일괄 생성한다.

## 브랜드 자산 두 종류 — 반드시 구분해서 쓴다

| 자산 | 파일 | 쓰는 곳 |
|---|---|---|
| **앱 아이콘(심볼)** | `assets/icon/app_icon.png` | 런처 아이콘 · 파비콘 · PWA · 부팅 스플래시 · 앱 안 정사각 로고 |
| **텍스트 로고(워드마크)** | `assets/brand/logo_wordmark.png` | 스플래시/로그인 화면의 `flownote` 글자 · 정산서 PDF 머리글 |

워드마크는 글자가 들어 있으므로 **정사각으로 잘리는 자리(런처 아이콘,
파비콘, 마스커블)에는 절대 쓰지 않는다.** 잘리면 글자가 깨진다.
반대로 심볼만으로는 브랜드명이 안 보이므로, 사람이 읽는 화면 상단에는
워드마크를 쓴다. 이 스크립트는 **심볼 쪽만** 생성한다.

## 🔴 새 아이콘은 모서리가 이미 둥글고 투명하다

이전 아이콘은 1254x1254 **꽉 찬 불투명 정사각**이었다. 새 아이콘은
스쿼클(둥근 사각) 모양이 원본에 그려져 있고 **네 모서리가 투명**이다.
(실측: 가운데 행은 x 22~1001 까지 불투명, 맨 윗줄은 x 288~735 뿐)

그래서 예전 코드를 그대로 쓰면 이런 문제가 난다.
  - iOS: 알파를 연한 로즈(#FDF0F0)로 평탄화하면 **모서리에 흰 테가 생긴다.**
    iOS 는 아이콘을 자체 스쿼클로 또 깎으므로, 원본 모서리를 그대로 두면
    "둥근 모서리 안에 또 둥근 모서리" 가 겹쳐 보인다.
  - Android `ic_launcher_round`: 이미 둥근 그림에 원형 마스크를 또 씌우면
    지름이 줄어들어 아이콘이 작아 보인다.
  - 마스커블/adaptive foreground: 잘려도 살아남아야 한다.

→ 아래 `squared()` 로 **모서리를 그라디언트 색으로 메워 꽉 찬 정사각**을
   먼저 만들고, 그 다음 각 플랫폼이 요구하는 모양으로 깎는다.
   그라디언트는 세로 방향이므로(실측: 좌우 색차 0~1) 행별 평균색으로
   모서리를 메우면 이어붙인 자리가 보이지 않는다.

생성 대상
  - android  mipmap-*/ic_launcher.png, ic_launcher_round.png      (레거시 런처)
  - android  mipmap-*/ic_launcher_foreground.png, _background.png (adaptive)
  - android  mipmap-anydpi-v26/ic_launcher{,_round}.xml           (adaptive 연결)
  - android  mipmap-*/launch_image.png                            (부팅 스플래시)
  - ios      AppIcon.appiconset/*.png            (알파 제거 — ITMS-90717)
  - ios      LaunchImage.imageset/LaunchImage{,@2x,@3x}.png
  - web      icons/Icon-{192,512}.png, Icon-maskable-{192,512}.png,
             icons/Icon-apple-180.png, favicon.png

🔴 부팅 스플래시도 여기서 만든다 (Build 26 부터)

  이전에는 `launch_image.png` 가 손으로 넣은 파일이어서 앱 아이콘과
  **그림이 달랐다.** 부팅 순간에는 주황 튤립이 보이고, Flutter 가 첫
  프레임을 그리는 순간 분홍 장미로 바뀌었다. 켜자마자 브랜드가 두 번
  바뀌는 셈이었다. iOS 쪽은 아예 1x1 빈 이미지였다.
  아이콘과 스플래시는 같은 원본에서 같이 만들어야 어긋나지 않는다.

사용: python3 tool/gen_icons.py
"""

import os

from statistics import median

import numpy as np

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "icon", "app_icon.png")

# 연한 로즈. 알파 평탄화의 최후 수단으로만 쓴다.
#
# 🔴 새 아이콘에서는 이 색이 거의 보이지 않아야 정상이다. 모서리는
#    `squared()` 가 그라디언트 색으로 메우므로, 이 값이 눈에 보인다면
#    squared() 가 동작하지 않았다는 뜻이다.
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

# 새 아이콘에 그려져 있는 스쿼클의 곡률. 실측값이다.
#
#   불투명 구간을 행별로 훑으면 맨 윗줄은 x 288~735 뿐이고, y=296 에서야
#   x 22~1001(전체 폭)에 닿는다. 즉 모서리가 약 280px 만큼 깎여 있다.
#   280 / 1024 = 0.273.
#
# 예전 값 22/84 = 0.262 보다 크다. 그래서 예전처럼 22/84 로 다시 깎으면
# 원본보다 **덜** 둥글게 잘려 모서리가 각져 보인다.
CORNER = 0.273

# adaptive icon / maskable 안전영역. 캔버스 대비 로고 크기.
#
#   Android adaptive icon 은 108dp 중 가운데 72dp 만 보장한다 → 72/108 = 0.667
#   PWA maskable 도 같은 규격을 권장한다.
# 원본이 이미 스쿼클이므로 여기서 더 줄이면 아이콘만 작아 보인다.
SAFE = 72 / 108

# 스쿼클 테두리 하이라이트를 걷어낼 침식 폭 (원본 1024 기준 픽셀).
#
# 🔴 이걸 몰라서 처음엔 모서리에 유령 곡선이 남았다.
#    원본 스쿼클 가장자리에는 유리처럼 밝은 얇은 테두리가 그려져 있다.
#    실측: 가운데 행에서 알파는 x=22 부터 시작하지만, 색이 그라디언트
#    직선과 맞아떨어지는(색차<=3) 지점은 x=31 이다. 위쪽은 y=16 에서
#    시작해 y=25 부터 깨끗하고, 아래쪽은 y=989 까지 깨끗하다.
#    → 테두리 폭 ≈ 9px.
#
#    이 테두리를 그대로 두고 모서리만 그라디언트로 메우면, 꽉 찬 정사각
#    안에 **원래 스쿼클의 윤곽선만 밝은 곡선으로 떠 있는** 그림이 된다.
#    (확대해서 눈으로 확인했다. 실제로 보였다.)
#
# 🔴 둥근사각 마스크로 깎는 방법은 실패했다.
#    `rounded_rectangle(radius=CORNER)` 로 안쪽만 남겨 봤더니, 곡선
#    구간에서 실제 스쿼클과 모양이 미세하게 달라 접선부에 테두리가
#    남았다(책 밖 영역 최대 색차 11). PIL 의 둥근사각은 원호이고 원본은
#    연속곡률 스쿼클이라 애초에 겹치지 않는다.
#
# → **알파를 직접 침식(erode)** 한다. MinFilter 는 이웃 최소값을 취하므로
#   모양이 무엇이든 그 윤곽에서 정확히 N px 안쪽으로 줄어든다.
#   실측 비교(책 밖 영역 최대 색차):
#       둥근사각 마스크  11
#       침식  7px         9
#       침식 10px         5   ← 채택 (남은 5 는 책 그림자, 테두리 아님)
#       침식 15px         5   (더 깎아도 나아지지 않는다)
ERODE = 14 / 1024


def load() -> Image.Image:
    im = Image.open(SRC).convert("RGBA")
    # 정사각 보정
    if im.width != im.height:
        s = min(im.width, im.height)
        left = (im.width - s) // 2
        top = (im.height - s) // 2
        im = im.crop((left, top, left + s, top + s))
    # 🔴 투명 모서리의 RGB 가 (0,0,0) 이라 그대로 줄이면 검은 실선이
    #    생긴다. 바로 그라디언트로 메워 둔다 (`matte` 설명 참고).
    return matte(im, gradient_of(im))


# 그라디언트 표본을 뜰 좌우 여백 띠.
#
# 🔴 흰 책을 색 기준으로 걸러내려 했더니 실패했다.
#    책 테두리의 부드러운 그림자가 (253,195,197) 이어서 "r>240 and
#    g>195 and b>195" 필터를 아슬아슬하게 통과했고, 책이 넓은 y=612
#    행에서 대표색이 (253,195,197) 로 튀었다. 직선에서 58 이나 벗어난
#    값이라, 그대로 쓰면 그 높이의 모서리에 밝은 띠가 생겼다.
#
# → 색으로 거르지 말고 **위치로 거른다.** 책 bbox 는 x 224~800 이므로
#   좌우 여백(x 40~180, 844~984)만 표본으로 쓴다. 여기엔 책이 없다.
#   x<22 / x>1001 은 스쿼클 테두리 하이라이트라 역시 피한다.
BANDS = list(range(40, 181, 4)) + list(range(844, 985, 4))


def gradient_of(im: Image.Image):
    """세로 그라디언트를 **직선으로 적합**해 `y -> (r,g,b)` 함수를 돌려준다.

    행별 평균/중앙값을 그대로 쓰지 않고 직선으로 적합하는 이유:
      - 위·아래 끝 행은 스쿼클 때문에 표본이 거의 없다(y<51, y>958).
        그 구간을 채우려면 어차피 외삽이 필요하다.
      - 표본이 조금이라도 오염되면 그 행만 색이 튀어 가로줄이 생긴다.
        직선은 800 행의 정보를 모두 쓰므로 한두 행의 잡음에 흔들리지 않는다.

    실측 결과 이 아이콘은 거의 완벽한 직선이었다.
        r = 255           (변화 없음)
        g = 172.8 - 0.0631*y
        b = 144.6 - 0.0270*y
        표본 대비 최대 오차 2/255
    적합 오차가 크면(그라디언트가 아니거나 방향이 다르면) 경고를 낸다.
    """
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()

    samples = []  # (y, (r,g,b))
    for y in range(h):
        vals = [px[x, y][:3] for x in BANDS if px[x, y][3] > 250]
        if len(vals) >= 30:
            samples.append((y, tuple(median(sorted(v[i] for v in vals)) for i in range(3))))
    if len(samples) < 50:
        # 그라디언트가 아니거나 모양이 완전히 다르다 → 가운데 색 한 개로 버틴다
        c = px[w // 2, h // 2][:3]
        print(f"  ! 그라디언트 표본 부족({len(samples)}행) — 단색 {c} 으로 대체")
        return lambda y: c

    coef = []
    worst = 0.0
    n = len(samples)
    sx = sum(y for y, _ in samples)
    sxx = sum(y * y for y, _ in samples)
    for ch in range(3):
        sy = sum(c[ch] for _, c in samples)
        sxy = sum(y * c[ch] for y, c in samples)
        den = n * sxx - sx * sx
        b = (n * sxy - sx * sy) / den if den else 0.0
        a = (sy - b * sx) / n
        coef.append((a, b))
        worst = max(worst, max(abs(a + b * y - c[ch]) for y, c in samples))

    print(f"  그라디언트 적합: y {samples[0][0]}~{samples[-1][0]} "
          f"({n}행), 최대오차 {worst:.1f}/255")
    if worst > 12:
        print("  ! 적합 오차가 크다 — 세로 그라디언트가 아닐 수 있다. 결과를 눈으로 확인할 것")

    def at(y: float):
        return tuple(max(0, min(255, round(a + b * y))) for a, b in coef)

    return at


def fill(at, size: int, y0: float, span: float) -> Image.Image:
    """`at` 그라디언트를 `size` 정사각에 칠한다.

    `y0`/`span` 은 **원본 좌표계 기준**이다. 캔버스의 y 픽셀이 원본의
    어느 높이에 해당하는지 알려 주면, 로고를 축소해 얹어도 배경 색이
    로고 경계에서 정확히 이어진다.
    """
    out = Image.new("RGBA", (size, size))
    d = ImageDraw.Draw(out)
    for y in range(size):
        d.line((0, y, size - 1, y), fill=at(y0 + span * y / max(1, size - 1)) + (255,))
    return out


def matte(im: Image.Image, at) -> Image.Image:
    """투명한 곳의 RGB 를 그라디언트 색으로 미리 메운다.

    🔴 PNG 는 straight alpha 다. 투명 픽셀도 RGB 값을 그대로 들고 있고,
    크기를 줄이면 리샘플러가 **그 값까지 섞어 버린다.** 새 아이콘에서
    이게 두 가지 실선으로 나타났다.
      - 투명 모서리의 RGB 는 (0,0,0) → 아이콘 둘레에 **검은 실선**
      - `clean()` 으로 깎아낸 자리는 유리 테두리 하이라이트 색 →
        adaptive 전경 경계에 **흰 실선** (측정 색차 36/255, 눈에도 보임)

    알파를 곱해서 줄이는 premultiplied 방식도 시도했지만, LANCZOS 의
    오버슈트 때문에 알파가 작은 경계에서 나눗셈이 값을 튀게 만들어
    흰 실선이 그대로 남았다. 그래서 **투명한 곳을 어차피 뒤에 깔릴
    그라디언트 색으로 채워 둔다.** 그러면 RGB 가 경계에서 연속이 되어
    리샘플링해도 섞일 이물질이 없고, 알파만 독립적으로 줄어든다.
    """
    im = im.convert("RGBA")
    a = np.asarray(im).copy()
    h, w = a.shape[0], a.shape[1]
    row = np.array([at(y * (h - 1) / max(1, h - 1)) for y in range(h)], dtype=np.uint8)
    fill = np.repeat(row[:, None, :], w, axis=1)
    hole = a[:, :, 3] < 250
    rgb = a[:, :, :3]
    rgb[hole] = fill[hole]
    a[:, :, :3] = rgb
    return Image.fromarray(a, "RGBA")


def clean(im: Image.Image) -> Image.Image:
    """테두리 하이라이트를 걷어낸 원본. 알파를 `ERODE` 만큼 침식한다.

    `MinFilter(k)` 는 각 픽셀을 반경 (k-1)/2 이웃의 최솟값으로 바꾼다.
    알파에 적용하면 불투명 영역이 그 반경만큼 **모양 그대로** 줄어든다.
    스쿼클이든 무엇이든 윤곽을 따라가므로 둥근사각 근사보다 정확하다.

    먼저 알파를 0/255 로 이진화한다. 원본 가장자리에는 반투명 안티앨리어싱
    픽셀이 있고, 이진화하지 않으면 침식이 그 값에 끌려 들어간다.
    """
    im = im.convert("RGBA")
    a = im.split()[3]
    k = max(3, int(round(im.width * ERODE)) * 2 + 1)  # MinFilter 는 홀수만 받는다
    hard = a.point(lambda v: 255 if v > 250 else 0)
    out = im.copy()
    out.putalpha(ImageChops.multiply(a, hard.filter(ImageFilter.MinFilter(k))))
    # 깎아낸 자리에 남은 테두리 하이라이트 RGB 를 그라디언트로 덮는다.
    return matte(out, gradient_of(im))


def squared(im: Image.Image) -> Image.Image:
    """둥근 모서리의 투명 부분을 **그라디언트 색으로 메워** 꽉 찬 정사각으로.

    새 아이콘은 스쿼클 모양이 원본에 그려져 있고 모서리가 투명하다.
    그 상태로 iOS 아이콘을 만들면 모서리에 연한 로즈 테가 남고, 원형
    마스크를 씌우면 아이콘이 작아 보인다. (자세한 이유는 파일 상단 doc)
    """
    im = im.convert("RGBA")
    base = fill(gradient_of(im), im.width, 0, im.height - 1)
    # 🔴 원본을 그대로 얹지 않고 `clean()` 으로 테두리를 걷어낸다.
    #    그대로 얹으면 정사각 안에 원래 스쿼클 윤곽선이 유령처럼 남는다.
    return Image.alpha_composite(base, clean(im))


def bleed(im: Image.Image, size: int, inner_ratio: float) -> Image.Image:
    """캔버스를 꽉 채운 그라디언트 + 가운데 안전영역 크기의 원본.

    adaptive icon / maskable 용이다. 이 둘은 캔버스의 일부만 보이고
    런처·브라우저가 마음대로 모양을 깎으므로, 로고는 안전영역 안에
    넣고 배경은 끝까지 채워야 한다.

    배경 그라디언트를 **로고와 같은 배율로 역산**해 칠하기 때문에
    로고 스쿼클 경계에서 색차가 0 이다 — 경계선이 아예 보이지 않는다.
    """
    inner = max(1, int(size * inner_ratio))
    off = (size - inner) // 2
    h = im.height
    # 캔버스 y=off 가 원본 y=0, y=off+inner-1 이 원본 y=h-1 에 대응한다.
    # 그 대응을 캔버스 0~size-1 로 늘려 시작점/구간을 구한다.
    per = (h - 1) / max(1, inner - 1)          # 캔버스 1px 당 원본 px
    base = fill(gradient_of(im), size, -off * per, per * (size - 1))

    # 여기서도 테두리를 걷어낸다. 배경이 끝까지 칠해져 있으므로 테두리를
    # 남기면 그라디언트 위에 밝은 곡선만 떠 보인다.
    art = resize(clean(im), inner)
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    # 🔴 마스크 인자를 주면 안 된다. 투명 캔버스 위에 마스크로 붙이면
    #    PIL 이 RGB 를 캔버스의 (0,0,0) 과 섞어서 경계에 검은 실선이
    #    생긴다. 그냥 RGBA 를 그대로 복사한다.
    layer.paste(art, (off, off))
    return Image.alpha_composite(base, layer)


def resize(im: Image.Image, size: int) -> Image.Image:
    """단순 LANCZOS 축소.

    투명 영역의 RGB 는 `matte()` 가 미리 그라디언트로 채워 두므로
    RGB/알파를 따로 줄이는 기본 동작이 그대로 정답이 된다.
    """
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
    # 🔴 위와 같은 이유로 마스크 없이 복사한다 (검은 테두리 방지).
    canvas.paste(inner, (off, off))
    return canvas


def splash(width: int, height: int) -> Image.Image:
    """부팅 스플래시 한 장을 만든다.

    앱 안 스플래시 화면(`splash_ds_screen.dart`)과 같은 모습으로 맞춘다.
      - 로고: 원본 그대로 (새 아이콘은 스쿼클이 이미 그려져 있다)
      - 그림자: rgba(238,118,134,.22), blur 18, y+6
      - 배경: SPLASH_BG

    🔴 마스크를 다시 씌우지 않는다.
       예전에는 꽉 찬 정사각 원본을 r22/84 로 깎아서 둥글게 만들었다.
       새 원본은 이미 둥글다(실측 곡률 ≈ 0.273 > 22/84 ≈ 0.262). 여기에
       또 깎으면 모서리가 두 번 깎여 각져 보인다.

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
    logo = resize(src, box)

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
        radius=int(box * CORNER),
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
    src = load()          # 모서리가 둥글고 투명한 원본 (그림 그대로)
    sq = squared(src)     # 모서리를 그라디언트로 메운 꽉 찬 정사각
    print(f"source {os.path.relpath(SRC, ROOT)} {src.size[0]}x{src.size[1]}")
    print(f"  alpha {src.split()[3].getextrema()} -> squared {sq.split()[3].getextrema()}")

    # ── Android 레거시 런처 아이콘 ─────────────────────────────
    # `ic_launcher` 는 마스크 없이 그대로 그려진다. 원본이 이미 스쿼클이니
    # 투명 모서리를 살린 `src` 를 쓴다. (여기에 sq 를 쓰면 각진 정사각이 된다)
    #
    # `ic_launcher_round` 는 런처가 원형을 요구할 때 쓰는 그림이다. 이미
    # 둥근 `src` 에 원형 마스크를 씌우면 지름이 줄어 옆 아이콘보다 작아
    # 보이므로, **꽉 찬 `sq` 를 원으로 깎는다.**
    print("android launcher:")
    android = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for dpi, size in android.items():
        base = os.path.join(ROOT, "android/app/src/main/res", f"mipmap-{dpi}")
        save(resize(src, size), os.path.join(base, "ic_launcher.png"))
        save(rounded(resize(sq, size)), os.path.join(base, "ic_launcher_round.png"))

    # ── Android adaptive icon (API 26+) ──────────────────────
    # 🔴 예전에는 `ic_launcher_foreground.png` 를 만들어 놓고 **아무도 쓰지
    #    않았다.** `mipmap-anydpi-v26/ic_launcher.xml` 이 없었기 때문이다.
    #    이번에 XML 까지 같이 만들어 실제로 연결한다.
    #
    # adaptive icon 은 108dp 캔버스에 전경/배경 두 장을 겹치고, 런처가
    # 가운데 72dp 만 남기고 마음대로 깎는다. 그래서
    #   - 배경: 캔버스를 꽉 채운 그라디언트 (`gradient_canvas`)
    #   - 전경: 72/108 로 축소한 원본 (스쿼클 + 흰 책)
    # 로 나눈다. 배경 그라디언트를 전경과 같은 배율로 역산해 두었으므로
    # 전경 스쿼클 경계에서 색이 끊기지 않는다 — 어떤 모양으로 깎여도
    # "그라디언트 + 흰 책" 이 온전히 보인다.
    print("android adaptive:")
    adaptive = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
    for dpi, size in adaptive.items():
        base = os.path.join(ROOT, "android/app/src/main/res", f"mipmap-{dpi}")
        # 🔴 전경도 `clean()` 을 거친다. 원본 스쿼클에는 9px 유리
        #    테두리 하이라이트가 있어서, 같은 그라디언트 배경 위에
        #    그대로 얹으면 스쿼클 윤곽선만 밝게 떠 보인다.
        #    (미리보기 렌더로 눈으로 확인한 실제 결함이다.)
        save(padded(clean(src), size, SAFE), os.path.join(base, "ic_launcher_foreground.png"))
        # 🔴 배경 레이어에도 로고를 넣는다. adaptive icon 은 전경/배경을
        #    겹쳐 그리므로 배경에 로고가 있어도 가려져 보이지 않고,
        #    반대로 런처가 전경을 무시하는 예외 상황(구형 삼성 런처 등)
        #    에서도 브랜드가 남는다. 경계 색차는 0 이다.
        save(bleed(src, size, SAFE), os.path.join(base, "ic_launcher_background.png"))

    v26 = os.path.join(ROOT, "android/app/src/main/res/mipmap-anydpi-v26")
    os.makedirs(v26, exist_ok=True)
    xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!-- tool/gen_icons.py 가 생성한다. 손으로 고치지 말 것. -->\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@mipmap/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        '</adaptive-icon>\n'
    )
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        p = os.path.join(v26, name)
        with open(p, "w", encoding="utf-8") as f:
            f.write(xml)
        print(f"  {os.path.relpath(p, ROOT)}  adaptive-icon")

    # ── iOS (알파 없음) ───────────────────────────────────────
    # iOS 는 아이콘을 자체 스쿼클로 깎는다. 그래서 원본의 둥근 모서리를
    # 그대로 두면 "둥근 모서리 안에 또 둥근 모서리" 가 되고, 투명부를
    # 평탄화하면서 연한 로즈 테두리가 생긴다. **꽉 찬 `sq` 를 넘긴다.**
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
        save(flatten(resize(sq, size)), os.path.join(ios_dir, f"Icon-App-{name}.png"))

    # ── Web ──────────────────────────────────────────────────
    print("web:")
    web_dir = os.path.join(ROOT, "web/icons")
    for size in (192, 512):
        # purpose "any": 브라우저가 그대로 보여준다 → 둥근 원본 + 투명
        save(resize(src, size), os.path.join(web_dir, f"Icon-{size}.png"))
        # purpose "maskable": 원형까지 깎일 수 있다 → 그라디언트로 꽉 채운다
        save(bleed(src, size, SAFE), os.path.join(web_dir, f"Icon-maskable-{size}.png"))

    # iOS 홈 화면 추가용. 🔴 apple-touch-icon 은 알파가 있으면 iOS 가
    # 뒤를 **검게** 깔아 버린다. 반드시 불투명 `sq` 로 만든다.
    save(flatten(resize(sq, 180)), os.path.join(web_dir, "Icon-apple-180.png"))

    # 파비콘은 탭 배경이 밝을 수도 어두울 수도 있으니 알파를 살린다.
    save(resize(src, 64), os.path.join(ROOT, "web/favicon.png"))

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
