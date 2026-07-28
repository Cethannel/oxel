struct Globals {
  float2 res;
};

struct VS_Input {
  float2 p0;
  float2 p1;
  float4 color;
  uint vertex_id;
};

struct PS_Input {
  float4 vertex : SV_Position;
  float4 color;
};

[[vk::push_constant]]
Globals globals;

[shader("vertex")]
func vertexMain(input: VS_Input)->PS_Input {
  static float2 vertices[] = {
    { -1, -1 },
    { -1, +1 },
    { +1, -1 },
    { +1, +1 },
  };

  // "dst" => "destination" (on screen)
  float2 dst_half_size = (input.p1 - input.p0) / 2;
  float2 dst_center = (input.p1 + input.p0) / 2;
  float2 dst_pos = (vertices[input.vertex_id] * dst_half_size + dst_center);

  // package output
  PS_Input output = { 0 };
  output.vertex = float4(2 * dst_pos.x / globals.res.x - 1,
                         2 * dst_pos.y / globals.res.y - 1, 0, 1);
  output.color = input.color;
  return output;
}

struct PSOutput {
  float4 color : SV_Target0;
};

[shader("pixel")]
func fragmentMain(input: PS_Input)->PSOutput {
  PSOutput output = { 0 };
  output.color = input.color;
  return output;
}
