#version 300 es
precision mediump float;

in vec2 vTexCoord;        // camera texture coord
in vec2 vMaskCoord;       // mask texture coord (lip alpha)
out vec4 fragColor;

uniform sampler2D uCameraTex;
uniform sampler2D uMaskTex;

uniform vec3  uLipColor;   // 0–1 RGB
uniform float uIntensity;  // 0–1
uniform int   uFinish;     // 0 = matte, 1 = satin, 2 = glossy

// simple directional light (screen space)
const vec3 lightDir = normalize(vec3(-0.2, -0.4, 1.0));

float remap(float v, float a, float b, float c, float d) {
    return clamp((v - a) / (b - a), 0.0, 1.0) * (d - c) + c;
}

void main() {
    vec4 src = texture(uCameraTex, vTexCoord);
    float mask = texture(uMaskTex, vMaskCoord).a;  // 0..1 lip alpha

    if (mask < 0.01) {
        fragColor = src;
        return;
    }

    // base lip color from camera
    vec3 base = src.rgb;

    // lipstick target color
    vec3 target = uLipColor;

    // how strong we blend lipstick vs base
    float blend = uIntensity * mask;

    // ---------- FINISH PRESETS ----------
    float specStrength;
    float specPower;
    float contrastBoost;
    float saturationBoost;

    if (uFinish == 0) {
        // MATTE: low shine, higher contrast
        specStrength    = 0.05;
        specPower       = 32.0;
        contrastBoost   = 0.12;
        saturationBoost = 0.05;
    } else if (uFinish == 1) {
        // SATIN: medium shine, natural
        specStrength    = 0.14;
        specPower       = 48.0;
        contrastBoost   = 0.06;
        saturationBoost = 0.03;
    } else {
        // GLOSSY: strong highlight
        specStrength    = 0.28;
        specPower       = 64.0;
        contrastBoost   = 0.0;
        saturationBoost = 0.02;
    }

    // base lipstick blend
    vec3 mixed = mix(base, target, blend);

    // small saturation + contrast tweak so lips don't look flat
    float lum = dot(mixed, vec3(0.299, 0.587, 0.114));
    mixed = mix(vec3(lum), mixed, 1.0 + saturationBoost);   // sat
    mixed = mix(vec3(0.5), mixed, 1.0 + contrastBoost);     // contrast

    // fake normal from vertical gradient – highlight upper middle lip more
    float ny = remap(vMaskCoord.y, 0.2, 0.8, -1.0, 1.0);
    vec3 normal = normalize(vec3(0.0, ny, 1.0));
    float ndotl = max(dot(normal, lightDir), 0.0);

    // specular highlight
    float spec = pow(ndotl, specPower) * specStrength * blend;

    vec3 finalColor = mixed + vec3(spec);

    // clamp
    finalColor = clamp(finalColor, 0.0, 1.0);

    fragColor = vec4(finalColor, src.a);
}
