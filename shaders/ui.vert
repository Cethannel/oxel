#version 450
#extension GL_EXT_buffer_reference : require

struct VS_Input
{
	vec2 p0;
	vec2 p1;
	vec4 color;
	uint vertex_id;
};

layout (location = 0) out vec4 color;

layout(buffer_reference, std430) readonly buffer InputBuffer{ 
	VS_Input inputs[];
};

layout(push_constant) uniform constants {
	vec2 res;
	InputBuffer inputs;
} PushConstants;


void main()
{
  // static vertex array that we can index into
  // with our vertex ID
  vec2 vertices[] =
  {
    {-1, -1},
    {-1, +1},
    {+1, -1},
    {+1, +1},
  };

  VS_Input inp = PushConstants.inputs.inputs[gl_VertexIndex];

  // "dst" => "destination" (on screen)
  vec2 dst_half_size = (inp.p1 - inp.p0) / 2;
  vec2 dst_center = (inp.p1 + inp.p0) / 2;
  vec2 dst_pos =
    (vertices[inp.vertex_id] * dst_half_size + dst_center);

  // package output
  gl_Position = vec4(2 * dst_pos.x / PushConstants.res.x - 1,
                         2 * dst_pos.y / PushConstants.res.y - 1,
                         0,
                         1);
  color = inp.color;
}

