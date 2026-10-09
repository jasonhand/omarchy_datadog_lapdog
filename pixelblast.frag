#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 uResolution;
    float uTime;
    vec4 uColor;
    vec4 uClick;
    vec2 uPointer;
    float uPointerAge;
};

float bayer2(vec2 a) { a = floor(a); return fract(a.x / 2.0 + a.y * a.y * 0.75); }
float bayer4(vec2 a) { return bayer2(0.5*a)*0.25 + bayer2(a); }
float bayer8(vec2 a) { return bayer4(0.5*a)*0.25 + bayer2(a); }
float hash11(float n) { return fract(sin(n)*43758.5453); }
float noise3(vec3 p) {
    vec3 ip = floor(p), fp = fract(p);
    vec3 w = fp*fp*fp*(fp*(fp*6.0-15.0)+10.0);
    float n = dot(ip, vec3(1.0,57.0,113.0));
    float x00 = mix(hash11(n),hash11(n+1.0),w.x);
    float x10 = mix(hash11(n+57.0),hash11(n+58.0),w.x);
    float x01 = mix(hash11(n+113.0),hash11(n+114.0),w.x);
    float x11 = mix(hash11(n+170.0),hash11(n+171.0),w.x);
    return mix(mix(x00,x10,w.y),mix(x01,x11,w.y),w.z)*2.0-1.0;
}
float field(vec2 uv, float t) {
    vec3 p = vec3(uv*1.5,t);
    float frequency = 1.0, sum = 1.0;
    for (int i=0;i<5;i++) { sum += noise3(p*frequency); frequency *= 1.25; }
    return sum*0.5+0.5;
}
void main() {
    vec2 resolution = max(uResolution,vec2(1.0));
    vec2 screen = vec2(qt_TexCoord0.x,1.0-qt_TexCoord0.y)*resolution;
    float pixelSize = 7.0;
    vec2 coord = screen-resolution*0.5;
    vec2 pixelId = floor(coord/pixelSize);
    vec2 pixelUV = fract(coord/pixelSize);
    float cellSize = 8.0*pixelSize;
    vec2 uv = floor(coord/cellSize)*cellSize/resolution*vec2(resolution.x/resolution.y,1.0);
    float feed = field(uv,uTime*0.05)*0.5-0.65+(1.5-0.5)*0.3;
    if (uClick.w > 0.5) {
        vec2 click = vec2(uClick.x,resolution.y-uClick.y);
        vec2 cuv = (click-resolution*0.5-cellSize*0.5)/resolution*vec2(resolution.x/resolution.y,1.0);
        float t = max(uTime-uClick.z,0.0);
        float r = distance(uv,cuv);
        float ring = exp(-pow((r-0.4*t)/0.12,2.0));
        feed = max(feed,ring*exp(-t)*exp(-10.0*r)*1.5);
    }
    float bw = step(0.5,feed+bayer8(coord/pixelSize)-0.5);
    float jitter = 1.0+(fract(sin(dot(pixelId,vec2(127.1,311.7)))*43758.5453)-0.5)*0.5;
    float coverage = bw*jitter;
    float d = length(pixelUV-0.5)-sqrt(coverage)*0.25;
    float aa = max(0.0001,0.5*fwidth(d));
    float mask = coverage*(1.0-smoothstep(-aa,aa,d*2.0));
    vec2 norm = screen/resolution;
    float edge = min(min(norm.x,norm.y),min(1.0-norm.x,1.0-norm.y));
    mask *= smoothstep(0.0,0.25,edge);
    float alpha = clamp(mask,0.0,1.0)*uColor.a*qt_Opacity;
    fragColor = vec4(uColor.rgb*alpha,alpha);
}
