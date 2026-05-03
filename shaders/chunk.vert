#version 450
#extension GL_EXT_shader_explicit_arithmetic_types_int16 : require   // ← Add this
#extension GL_EXT_buffer_reference : require

const int CHUNK_WIDTH = 16;
const int CHUNK_HEIGHT = 256;

layout (location = 0) out vec3 outColor;
layout (location = 1) out vec2 outUV;

struct ModelEntry {
	vec3 position;
	float uv_x;
	vec3 normal;
	float uv_y;
	vec4 color;
}; 

struct Vertex {
	uint model_index;
	uint16_t packed_pos;
};

layout(buffer_reference, std430) readonly buffer VertexBuffer{ 
	Vertex vertices[];
};

layout(buffer_reference, std430) readonly buffer ModelBuffer{
	ModelEntry models[];
};

//push constants block
layout( push_constant ) uniform constants
{	
	mat4 render_matrix;
	VertexBuffer vertexBuffer;
	ModelBuffer modelBuffer;
} PushConstants;

void main() 
{	
	//load vertex data from device adress
	Vertex v = PushConstants.vertexBuffer.vertices[gl_VertexIndex];

	uint x =  v.packed_pos        & 0xF;
    uint y = (v.packed_pos >> 4)  & 0xFF;
    uint z = (v.packed_pos >> 12) & 0xF;

    vec3 pos = vec3(x, y, z);

	ModelEntry model = PushConstants.modelBuffer.models[v.model_index];

	//output data
	gl_Position = PushConstants.render_matrix * vec4(pos + model.position, 1.0f);
	outColor = model.color.xyz;
	outUV.x = model.uv_x;
	outUV.y = model.uv_y;
}

