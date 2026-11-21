#include <metal_stdlib>
using namespace metal;

struct MaterialVertex { float4 position, normal; float2 uv; };
struct Vertex { float4 position [[position]]; float2 uv; float3 normal; float drop; };
vertex Vertex clothVertex(uint id [[vertex_id]], const device MaterialVertex *mesh [[buffer(0)]],
                          constant float4& scene [[buffer(1)]]) {
    MaterialVertex v=mesh[id];
    // Orthographic camera with a slight oblique view so out-of-plane billows are visible.
    float2 projected=float2(v.position.x+.14*v.position.z,v.position.y-.04*v.position.z);
    return {float4(2.*projected.x/scene.x,1.-2.*projected.y/scene.y,
                   clamp(.50-v.position.z*.045,0.01,.99),1),v.uv,v.normal.xyz,projected.y};
}

float segment(float2 p, float2 a, float2 b) {
    float2 along=b-a;
    return length(p-a-clamp(dot(p-a,along)/dot(along,along),0.,1.)*along);
}
float curvedSeam(float2 p,float2 a,float2 control,float2 b) {
    float d=1., t;
    float2 last=a;
    for (int i=1;i<=8;i++) {
        t=float(i)/8.;
        float2 next=mix(mix(a,control,t),mix(control,b,t),t);
        d=min(d,segment(p,last,next));
        last=next;
    }
    return d;
}
float satinLine(float distance, float radius, float aa) {
    return 1.-smoothstep(radius-aa,radius+aa,abs(distance));
}
float star(float2 p) {
    float2 v=sqrt(abs(p));
    return (v.x+v.y)*(v.x+v.y);
}
float hash21(float2 p) {
    float3 q=fract(p.xyx*float3(.1031,.11369,.13787));
    q+=dot(q,q.yzx+19.19);
    return fract((q.x+q.y)*q.z);
}
// Smooth bilinear value noise: zero blocky pixel squares at any screen width or zoom.
float smoothNoise(float2 p) {
    float2 i=floor(p), f=fract(p);
    f=f*f*(3.-2.*f);
    float a=hash21(i), b=hash21(i+float2(1.,0.));
    float c=hash21(i+float2(0.,1.)), d=hash21(i+float2(1.,1.));
    return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}
float velvetFbm(float2 p) {
    float v=0., amp=.55;
    for (int i=0;i<3;i++) {
        v+=amp*(smoothNoise(p)-.5);
        p=float2(p.x*2.07-p.y*.63, p.x*.63+p.y*2.07);
        amp*=.48;
    }
    return v;
}
// Matches BannerCloth.cutoutOffset exactly so the gold hem border follows every cutout shape.
float cutoutOffset(float u, int cutout, float tail) {
    if (cutout == 1) return tail * (1. - abs(2.*u - 1.));           // swallowtail V-cut
    if (cutout == 2) return tail * abs(2.*u - 1.);                  // pointed heraldic pennant
    if (cutout == 3) return tail * cos((u - .5) * 3.14159265);      // grand theatrical arch
    if (cutout == 4) return tail * .5 * (1. - cos(6.*3.14159265*u));// scalloped valence waves
    return 0.;                                                      // straight hem (default)
}

// Radii and distances below are in physical reference units. Every stitch follows the cloth coordinates.
float embroidery(float2 p, float aa) {
    float2 q=float2(abs(p.x),p.y);
    float hood=curvedSeam(q,float2(0.,-.235),float2(.127,-.114),float2(.110,-.025));
    hood=min(hood,curvedSeam(q,float2(.110,-.025),float2(.078,.018),float2(0.,.041)));
    float edge=curvedSeam(q,float2(.074,.012),float2(.160,.085),float2(.180,.194));
    edge=min(edge,curvedSeam(q,float2(.180,.194),float2(.070,.114),float2(0.,.210)));
    float fold=curvedSeam(q,float2(.036,.052),float2(.055,.109),float2(.094,.141));
    float weight=max(satinLine(hood,.008,aa),satinLine(edge,.009,aa));
    weight=max(weight,.83*satinLine(fold,.0045,aa));
    float light=1.-smoothstep(.061-aa,.061+aa,star(float2(p.x*1.1,p.y+.072)));
    return max(weight,light);
}

// fabric: (collarDepth, bodyOpacity, style, tail)
// extra:  (widthScale, cutoutType, boardAspect, 0)
fragment float4 clothVelvet(Vertex in [[stage_in]],
                            constant float4& s [[buffer(0)]],
                            constant float4& fabric [[buffer(1)]],
                            constant float4& extra [[buffer(2)]],
                            texture2d<float> atlas [[texture(0)]],
                            texture2d<float> boardTex [[texture(1)]]) {
    float collar=fabric.x;
    float2 uv=in.uv;
    float length=s.z;
    float tail=fabric.w;
    float widthScale=max(0.75, extra.x);    // 1.0 = ~330 pt notch width; ~4.5 = near-full width
    int cutout=int(extra.y + 0.5);
    int style=int(fabric.z + 0.5);

    float y=uv.y;
    float hem=length - cutoutOffset(uv.x, cutout, tail);
    float2 physUV=uv * widthScale;          // physical fabric coords: identical crisp velvet grain at EVERY width!
    float aa=max(.00002, max(fwidth(uv.x), fwidth(uv.y)) * .66);
    float physAA=max(.00005, max(fwidth(physUV.x), fwidth(physUV.y)) * .66);

    // Distance to left/right edge and bottom hem in physical reference units (keeps border trim crisp & proportional).
    float borderScale = clamp(widthScale, 1.0, 2.8);
    float edgePhys = min(uv.x, 1. - uv.x) * borderScale;
    float turnPhys = (hem - y) * borderScale;
    float borderAA = max(.00005, aa * borderScale);

    float3 n=normalize(in.normal);
    if (n.z < 0.) n=-n;
    float3 key=normalize(float3(-.58,-.42,.82));
    // Cut pile absorbs direct light; grazing fibre rim illuminates velvet folds deeply.
    float direct=saturate(dot(n,key));
    float grazing=pow(1.-saturate(n.z),1.65);
    float pileLight=.70+.30*saturate(dot(n,normalize(float3(-.6,-.48,.14))));

    uint dye=uint(s.w+0.5);
    const float3 shadow[4]={float3(.010,.010,.012),float3(.048,.009,.018),float3(.008,.030,.018),float3(.012,.019,.046)};
    const float3 face[4]  ={float3(.072,.071,.079),float3(.255,.064,.090),float3(.050,.162,.098),float3(.072,.098,.200)};
    const float3 nap[4]   ={float3(.19,.18,.21),   float3(.28,.13,.155),  float3(.120,.192,.145),float3(.150,.165,.240)};
    float3 body=mix(shadow[dye],face[dye],pow(direct,1.45)*.78);
    body+=nap[dye]*grazing*pileLight;

    // 4K+ resolution-independent velvet micro-pile (smooth multi-octave fbm + fine anisotropic warp/weft, zero pixel blocks!)
    float2 fineYarn = physUV * float2(780., 520.);
    float weaveFade = 1. - smoothstep(.35, 1.4, max(fwidth(fineYarn.x), fwidth(fineYarn.y)));
    float microPile = velvetFbm(physUV * float2(140., 110.));
    float fineWeave = (smoothNoise(fineYarn + float2(physUV.y * 42., 0.)) - .5) * weaveFade;
    float warpRib = sin(physUV.x * 1650.) * .035 * weaveFade;
    float napFlow = sin(physUV.x * 11. + sin(physUV.y * 4.5)) * .22 + velvetFbm(physUV * 16.) * .32;

    // Ultra-fine glinting velvet tuft tips (smoothly resolved at 4K+ physical scale)
    float2 tuftGrid = physUV * float2(340., 230.);
    float2 tuft = fract(tuftGrid) - .5;
    float seed = hash21(floor(tuftGrid));
    float axis = tuft.x + tuft.y * (.48 + seed * .58);
    float fibreTip = exp(-axis * axis * 90.) * (1. - smoothstep(.04, .44, abs(tuft.y)));
    float tuftFade = 1. - smoothstep(.45, 1.45, max(fwidth(tuftGrid.x), fwidth(tuftGrid.y)));
    body *= 1. + (fineWeave * .22 + microPile * .24 + warpRib + napFlow * .09);
    body += float3(.020,.020,.024) * fibreTip * (.20 + .80 * seed) * tuftFade * (.26 + grazing);

    // Self-coloured damask: physical-scale staggered leaves, visible where grazing light catches velvet.
    float2 tile = physUV * float2(14., 12.);
    tile.x += .5 * fmod(floor(tile.y), 2.);
    float2 petal = fract(tile) - .5;
    float leaf = abs(petal.x + .42 * petal.y) + pow(abs(petal.y), 1.5);
    float motif = satinLine(leaf - .245, .034, min(.08, physAA * 12.));
    body += body * motif * (.025 + .095 * grazing);

    // Double braid with a twisted centre and a narrow row of antique-gold seed stitches.
    float twist = .0021 * sin(physUV.y * 340.);
    float border = max(satinLine(edgePhys - .0275 - twist, .0041, borderAA),
                       satinLine(edgePhys - .043, .0022, borderAA));
    float stitch = metal::length(float2((edgePhys - .064) * 1.7, (fract(physUV.y * 36.) - .5) / 36.));
    border = max(border, .86 * satinLine(stitch, .0036, borderAA));
    border = max(border, max(satinLine(turnPhys - .035, .0036, borderAA),
                             satinLine(turnPhys - .055, .0018, borderAA)));

    // Emblem / crest placed with true 1:1 physical aspect ratio (never stretched horizontally on wide curtains!).
    float usable = max(.10, length - collar - (cutout == 0 ? 0.0 : tail) - .08);
    float badgeScale = clamp(usable * 1.55, .20, .82);
    float2 emblem = float2((uv.x - .5), (uv.y - collar - .05 - min(usable * .47, .85))) / badgeScale;
    float crest = 0.;
    if (style == 0 && abs(emblem.x) < .21 && abs(emblem.y) < .26) crest = embroidery(emblem, aa / badgeScale);
    if (style == 6) {
        float glint = pow(saturate(dot(n, normalize(float3(-.36,.03,.93)))), 16.);
        body = mix(float3(.01,.065,.093), float3(.095,.37,.45), direct * .72) + glint * float3(.07,.17,.19);
        body *= 1. + (fineWeave * .14 + microPile * .12);
        float2 q = float2(abs(emblem.x), emblem.y);
        float forks = min(segment(q, float2(.197,-.17), float2(.088,-.015)),
                          segment(q, float2(.088,-.015), float2(.192,.155)));
        crest = max(satinLine(forks, .014, aa / badgeScale),
                    1. - smoothstep(.082 - aa / badgeScale, .082 + aa / badgeScale, star(emblem)));
    }
    float2 heel = float2(uv.x - .5, (length - y) - .385);
    float jewel = abs(heel.x) + .44 * abs(heel.y);
    crest = max(crest, smoothstep(1.34, 1.65, length) * .78 * satinLine(jewel - .032, .0029, aa));

    float bullion = .5 + .5 * sin((physUV.y * 1.8 + physUV.x) * 860.);
    float3 stitchColor = mix(float3(.115,.102,.090), float3(.52,.47,.39), saturate(.15 + .56 * direct + .27 * grazing));
    if (style == 6) stitchColor = mix(float3(.49,.30,.105), float3(1.,.83,.46), direct);
    stitchColor *= .86 + .14 * mix(.5, bullion, weaveFade);
    float3 color = mix(body, stitchColor, max(crest, border * .74));

    // 8K Mathematical notebook & 4K-per-tile plates (aspect-preserving, zero stretching, 16x anisotropic!)
    if (style > 0 && style < 6) {
        constexpr sampler printSampler(coord::normalized, address::repeat, filter::linear,
                                       mip_filter::linear, max_anisotropy(16));
        float edging = smoothstep(.058, .078, edgePhys) * smoothstep(.052, .078, turnPhys);
        float2 printUV;
        float printMask = 1.;
        if (style == 1) {
            // Physical-scale repeating mathematical notebook (never stretched horizontally on wide curtains!)
            float tileW = 0.85 / widthScale;
            float tileH = tileW * 0.875;
            printUV = float2((uv.x - .5) / max(tileW, 0.12) + .5, (uv.y - collar - .025) / max(tileH, 0.12));
        } else {
            // Preserve true 1:1 aspect ratio for each 4K plate tile, centered cleanly in the usable region!
            float padX = 0.085 / borderScale;
            float padTop = collar + 0.032;
            float padBot = (cutout == 0 ? 0.0 : tail * 0.72) + 0.072 / borderScale;
            float availW = max(0.15, 1.0 - 2.0 * padX);
            float availH = max(0.14, length - padTop - padBot);
            float box = min(availW, availH * 1.12);
            float boxW = box;
            float boxH = min(availH, box);
            float2 panel = float2((uv.x - (0.5 - boxW * 0.5)) / boxW,
                                  (uv.y - (padTop + (availH - boxH) * 0.5)) / boxH);
            int tileID = style - 2;
            printMask = all(panel >= 0.002) && all(panel <= 0.998) ? 1. : 0.;
            printUV = (clamp(panel, .001, .999) + float2(tileID % 2, tileID / 2)) * .5;
        }
        float ink = atlas.sample(printSampler, printUV, gradient2d(dfdx(printUV), dfdy(printUV))).r;
        float3 whiteThread = mix(float3(.76,.77,.79), float3(1.,.99,.97), direct);
        color = mix(color, whiteThread, min(1., ink * 1.18) * edging * printMask);
    }

    // Style 7: 4K Live Useful Info Board (Digest / Dashboard / Custom Text woven onto the waving velvet!)
    if (style == 7) {
        constexpr sampler boardSampler(coord::normalized, address::clamp_to_edge, filter::linear,
                                       mip_filter::linear, max_anisotropy(16));
        float padX = 0.078 / borderScale;
        float padTop = collar + 0.024;
        float padBot = (cutout == 0 ? 0.0 : tail * 0.78) + 0.068 / borderScale;
        float availW = max(0.15, 1.0 - 2.0 * padX);
        float availH = max(0.12, length - padTop - padBot);
        float2 bUV = float2((uv.x - padX) / availW, (uv.y - padTop) / availH);
        float inside = all(bUV >= 0.) && all(bUV <= 1.) ? 1. : 0.;
        float edging = smoothstep(.058, .078, edgePhys) * smoothstep(.052, .078, turnPhys) * inside;
        float4 sample = boardTex.sample(boardSampler, clamp(bUV, 0., 1.),
                                        gradient2d(dfdx(bUV), dfdy(bUV)));
        // Light the woven gold/ivory typography with the 3D velvet fold illumination while keeping it crisp & legible!
        float3 litInk = sample.rgb * (0.64 + 0.42 * direct + 0.16 * grazing);
        color = mix(color, litInk, sample.a * edging);
    }

    // The upper collar unites the two shoulders and camera cutout in a single
    // uninterrupted black surface. Scaled by borderScale so Ultra Short curtains show crisp velvet.
    // extra.z = collarOpacity (1.0 at rest; fades smoothly when hovering near the top border).
    float reveal = smoothstep(collar, collar + .034 / borderScale, in.drop);
    color = mix(float3(.004,.004,.006) * (1. + .14 * fineWeave), color, reveal);
    float collarAlpha = extra.z > 0.0001 ? extra.z : 1.0;
    if (extra.w > 0.5) collarAlpha = extra.z;
    float coverage = mix(collarAlpha, fabric.y, reveal);
    return float4(color * coverage, coverage);
}
