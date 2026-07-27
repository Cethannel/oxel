[format("rgba16f")]
[[vk::binding(0, 0)]]
RWTexture2D<float4> image;

struct PushConstants {
  float4 data1;
  float4 data2;
  float4 data3;
  float4 data4;
};

layout(push_constant) ConstantBuffer<PushConstants> constants;

func Noise2d(x: float2)->float {
  float xhash = cos(x.x * 37.0);
  float yhash = cos(x.y * 57.0);
  return fract(415.92653 * (xhash + yhash));
}

func NoisyStarField(in vSamplePos: float2, fThreshhold: float)->float {
  float StarVal = Noise2d(vSamplePos);
  if (StarVal >= fThreshhold)
    StarVal = pow((StarVal - fThreshhold) / (1.0 - fThreshhold), 6.0);
  else
    StarVal = 0.0;
  return StarVal;
}

// Stabilize NoisyStarField() by only sampling at integer values.
func StableStarField(in vSamplePos: float2, fThreshhold: float)->float {
  // Linear interpolation between four samples.
  // Note: This approach has some visual artifacts.
  // There must be a better way to "anti alias" the star field.
  float fractX = fract(vSamplePos.x);
  float fractY = fract(vSamplePos.y);
  float2 floorSample = floor(vSamplePos);
  float v1 = NoisyStarField(floorSample, fThreshhold);
  float v2 = NoisyStarField(floorSample + float2(0.0, 1.0), fThreshhold);
  float v3 = NoisyStarField(floorSample + float2(1.0, 0.0), fThreshhold);
  float v4 = NoisyStarField(floorSample + float2(1.0, 1.0), fThreshhold);

  float StarVal = v1 * (1.0 - fractX) * (1.0 - fractY) +
                  v2 * (1.0 - fractX) * fractY + v3 * fractX * (1.0 - fractY) +
                  v4 * fractX * fractY;
  return StarVal;
}

func mainImage(out fragColor: float4, in fragCoord: int2)->void {
  float2 iResolution;
  image.GetDimensions(iResolution.x, iResolution.y);
  // Sky Background Color
  // vec3 vColor = vec3( 0.1, 0.2, 0.4 ) * fragCoord.y / iResolution.y;
  float3 vColor = constants.data1.xyz * fragCoord.y / iResolution.y;

  // Note: Choose fThreshhold in the range [0.99, 0.9999].
  // Higher values (i.e., closer to one) yield a sparser starfield.
  float StarFieldThreshhold = constants.data1.w; // 0.97;

  // Stars with a slow crawl.
  float xRate = 0.2;
  float yRate = -0.06;
  float2 vSamplePos = fragCoord.xy + float2(xRate * float(1), yRate * float(1));
  float StarVal = StableStarField(vSamplePos, StarFieldThreshhold);
  vColor += float3(StarVal);

  fragColor = float4(vColor, 1.0);
}

func imageSize(image: RWTexture2D)->int2 {
  int2 size;
  image.GetDimensions(size.x, size.y);
  return size;
}

[shader("compute")]
[numthreads(16, 16, 1)]
void main(uint3 globalID: SV_DispatchThreadID,
          uint3 localID: SV_GroupThreadID) {
  float4 value = float4(0.0, 0.0, 0.0, 1.0);
  int2 texelCoord = int2(globalID.xy);
  int2 size = imageSize(image);
  if (texelCoord.x < size.x && texelCoord.y < size.y) {
    float4 color;
    mainImage(color, texelCoord);

    image[texelCoord] = color;
  }
}
