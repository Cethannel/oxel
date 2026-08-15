struct Globals {
  float2 res;
  Texture2D texture;
};

struct VS_Input {
  oat2 dst_p0;   // top left corner on screen
  float2 dst_p1; // bottom right corner on screen
  float2 src_p0; // top left corner on texture
  float2 src_p1; // bottom right corner on texture
  float4 color;
  uint vertex_id;
};

struct PS_Input {
  float4 vertex : SV_Position;
  float2 uv;
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
  float2 dst_half_size = (input.dst_p1 - input.dst_p0) / 2;
  float2 dst_center = (input.dst_p1 + input.dst_p0) / 2;
  float2 dst_pos = (vertices[input.vertex_id] * dst_half_size + dst_center);

  // "src" => "source" (on texture)
  float2 src_half_size = (input.src_p1 - input.src_p0) / 2;
  float2 src_center = (input.src_p1 + input.src_p0) / 2;
  float2 src_pos = (vertices[input.vertex_id] * src_half_size + src_center);

  float2 size = { 0 };
  globals.texture.GetDimensions(size.x, size.y);

  // package output
  PS_Input output = { 0 };
  output.vertex = float4(2 * dst_pos.x / globals.res.x - 1,
                         2 * dst_pos.y / globals.res.y - 1, 0, 1);
  output.uv = float2(src_pos.x / size.x, src_pos.y / size.y);
  output.color = input.color;
  return output;
}

struct PSOutput {
  float4 color : SV_Target0;
};

[shader("pixel")]
func fragmentMain(input: PS_Input)->PSOutput {
  float4 sample = SampleTexture2D(globals.texture, input.uv);
  float4 color = input.color * sample;
  return color;
}
