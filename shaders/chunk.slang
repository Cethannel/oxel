
struct VOut {
  float4 position : SV_Position;
  float3 color;
  float2 uv;
  float3 normal;
}

struct Vertex {
  uint model_index;
  uint16_t packed_pos;
};

struct ModelEntry {
  float3 position;
  float uv_x;
  float3 normal;
  float uv_y;
  float4 color;
};

struct PushConstants {
  matrix<float, 4, 4> render_matrix;
  Vertex *vertexBuffer;
  ModelEntry *modelBuffer;
};

[[vk::push_constant]]
PushConstants pushConstants;

[shader("vertex")]
VOut vertexMain(uint vertexID: SV_VertexID) {

  Vertex v = pushConstants.vertexBuffer[vertexID];

  uint x = v.packed_pos & 0xF;
  uint y = (v.packed_pos >> 4) & 0xFF;
  uint z = (v.packed_pos >> 12) & 0xF;

  float3 pos = float3(x, y, z);

  ModelEntry model = pushConstants.modelBuffer[v.model_index];

  VOut output;

  output.position =
      mul(pushConstants.render_matrix, float4(pos + model.position, 1.0));

  output.color = model.color.rgb;
  output.uv.x = model.uv_x;
  output.uv.y = model.uv_y;
  output.normal = model.normal;

  return output;
}

struct PSOutput {
  float4 color : SV_Target0;
};

layout(set = 0, binding = 0) Sampler2D displayTexture;

[shader("pixel")]
PSOutput fragmentMain(VOut input) {
  PSOutput output;

  output.color = displayTexture.Sample(input.uv);

  if (input.normal.x != 0) {
      output.color.rgb *= 0.9;
  } else if (input.normal.y != 0) {
    output.color.rgb *= 0.85;
  }

  return output;
}

