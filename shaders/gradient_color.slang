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

[shader("compute")]
[numthreads(16, 16, 1)]
void main(uint3 globalID: SV_DispatchThreadID,
          uint3 localID: SV_GroupThreadID) {
  int2 texelCoord = int2(globalID.xy);
  int2 size;
  image.GetDimensions(size.x, size.y);

  float4 topColor = constants.data1;
  float4 bottomColor = constants.data2;

  if (texelCoord.x < size.x && texelCoord.y < size.y) {
    float blend = float(texelCoord.y) / (size.y);

    image[texelCoord] = lerp(topColor, bottomColor, blend);
  }
}
