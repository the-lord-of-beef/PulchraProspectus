#version 120
#extension GL_EXT_gpu_shader4 : enable
#extension GL_ARB_shader_texture_lod : enable

//#define POM
#define POM_MAP_RES 128.0 // [16.0 32.0 64.0 128.0 256.0 512.0 1024.0] Increase to improve POM quality
#define POM_DEPTH 0.1 // [0.025 0.05 0.075 0.1 0.125 0.15 0.20 0.25 0.30 0.50 0.75 1.0] //Increase to increase POM strength
#define MAX_ITERATIONS 50 // [5 10 15 20 25 30 40 50 60 70 80 90 100 125 150 200 400] //Improves quality at grazing angles (reduces performance)
#define MAX_DIST 25.0 // [5.0 10.0 15.0 20.0 25.0 30.0 40.0 50.0 60.0 70.0 80.0 90.0 100.0 125.0 150.0 200.0 400.0] //Increases distance at which POM is calculated
//#define USE_LUMINANCE_AS_HEIGHTMAP	//Can generate POM on any texturepack (may look weird in some cases)

//#define DISABLE_ALPHA_MIPMAPS //Disables mipmaps on the transparency of alpha-tested things like foliage, may cost a few fps in some cases
#ifndef USE_LUMINANCE_AS_HEIGHTMAP
#ifndef MC_NORMAL_MAP
#undef POM
#endif
#endif

#ifdef POM
#define MC_NORMAL_MAP
#endif

const float mincoord = 1.0/4096.0;
const float maxcoord = 1.0-mincoord;
const vec3 intervalMult = vec3(1.0, 1.0, 1.0/POM_DEPTH)/POM_MAP_RES * 1.0;

const float MAX_OCCLUSION_DISTANCE = MAX_DIST;
const float MIX_OCCLUSION_DISTANCE = MAX_DIST*0.9;
const int   MAX_OCCLUSION_POINTS   = MAX_ITERATIONS;


#ifdef POM
varying vec4 vtexcoordam; // .st for add, .pq for mul
varying vec4 vtexcoord;
uniform vec2 texelSize;
uniform int framemod8;
#endif

varying vec4 lmtexcoord;
varying vec4 color;
 varying vec4 normalMat;
#ifdef MC_NORMAL_MAP
varying vec4 tangent;
uniform float wetness;
uniform sampler2D normals;
#endif
#ifdef POM
vec2 dcdx = dFdx(vtexcoord.st*vtexcoordam.pq);
vec2 dcdy = dFdy(vtexcoord.st*vtexcoordam.pq);
#endif
uniform sampler2D texture;
uniform float frameTimeCounter;
uniform mat4 gbufferProjectionInverse;
float interleaved_gradientNoise(){
	return fract(52.9829189*fract(0.06711056*gl_FragCoord.x + 0.00583715*gl_FragCoord.y)+frameTimeCounter*51.9521);
}

//encode normal in two channels (xy),torch(z) and sky lightmap (w)
vec4 encode (vec3 n)
{

    return vec4(n.xy*inversesqrt(n.z*8.0+8.0) + 0.5,vec2(lmtexcoord.z,lmtexcoord.w));
}

#ifdef MC_NORMAL_MAP
vec3 applyBump(mat3 tbnMatrix, vec3 bump)
{

		float bumpmult = 1.0-wetness*0.95;

		bump = bump * vec3(bumpmult, bumpmult, bumpmult) + vec3(0.0f, 0.0f, 1.0f - bumpmult);

		return normalize(bump*tbnMatrix);
}
#endif

//encoding by jodie
float encodeVec2(vec2 a){
    const vec2 constant1 = vec2( 1., 256.) / 65535.;
    vec2 temp = floor( a * 255. );
	return temp.x*constant1.x+temp.y*constant1.y;
}
float encodeVec2(float x,float y){
    return encodeVec2(vec2(x,y));
}

#define diagonal3(m) vec3((m)[0].x, (m)[1].y, m[2].z)
#define  projMAD(m, v) (diagonal3(m) * (v) + (m)[3].xyz)
vec3 toScreenSpace(vec3 p) {
	vec4 iProjDiag = vec4(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y, gbufferProjectionInverse[2].zw);
    vec3 p3 = p * 2. - 1.;
    vec4 fragposition = iProjDiag * p3.xyzz + gbufferProjectionInverse[3];
    return fragposition.xyz / fragposition.w;
}
#ifdef POM
vec4 readNormal(in vec2 coord)
{
	return texture2DGradARB(normals,fract(coord)*vtexcoordam.pq+vtexcoordam.st,dcdx,dcdy);
}
vec4 readTexture(in vec2 coord)
{
	return texture2DGradARB(texture,fract(coord)*vtexcoordam.pq+vtexcoordam.st,dcdx,dcdy);
}
#endif
float luma(vec3 color) {
	return sqrt(dot(color*color,vec3(0.299, 0.587, 0.114)));
}

		const vec2[8] offsets = vec2[8](vec2(1./8.,-3./8.),
									vec2(-1.,3.)/8.,
									vec2(5.0,1.)/8.,
									vec2(-3,-5.)/8.,
									vec2(-5.,5.)/8.,
									vec2(-7.,-1.)/8.,
									vec2(3,7.)/8.,
									vec2(7.,-7.)/8.);
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
/* DRAWBUFFERS:1 */
void main() {
	float noise = interleaved_gradientNoise();
	vec3 normal = normalMat.xyz;
	#ifdef MC_NORMAL_MAP
		vec3 tangent2 = normalize(cross(tangent.rgb,normal)*tangent.w);
		mat3 tbnMatrix = mat3(tangent.x, tangent2.x, normal.x,
								  tangent.y, tangent2.y, normal.y,
						     	  tangent.z, tangent2.z, normal.z);
	#endif

#ifdef POM
		vec2 tempOffset=offsets[framemod8];
		vec2 adjustedTexCoord = fract(vtexcoord.st)*vtexcoordam.pq+vtexcoordam.st;
		vec3 fragpos = toScreenSpace(gl_FragCoord.xyz*vec3(texelSize,1.0)-vec3(vec2(tempOffset)*texelSize*0.5,0.0));
		vec3 viewVector = normalize(tbnMatrix*fragpos);
		float dist = length(fragpos);
if (dist < MAX_OCCLUSION_DISTANCE) {
	#ifndef USE_LUMINANCE_AS_HEIGHTMAP
		if ( viewVector.z < 0.0 && readNormal(vtexcoord.st).a < 0.9999 && readNormal(vtexcoord.st).a > 0.00001)
	{
		vec3 interval = viewVector.xyz * intervalMult;
		vec3 coord = vec3(vtexcoord.st, 1.0);
		coord += noise*interval;

		for (int loopCount = 0;
				(loopCount < MAX_OCCLUSION_POINTS) && (readNormal(coord.st).a < coord.p) &&coord.p >= 0.0;
				++loopCount) {
			coord = coord+interval;

		}
		if (coord.t < mincoord) {
			if (readTexture(vec2(coord.s,mincoord)).a == 0.0) {
				coord.t = mincoord;
				discard;
			}
		}
		adjustedTexCoord = mix(fract(coord.st)*vtexcoordam.pq+vtexcoordam.st , adjustedTexCoord , max(dist-MIX_OCCLUSION_DISTANCE,0.0)/(MAX_OCCLUSION_DISTANCE-MIX_OCCLUSION_DISTANCE));
	}
	#else
	if ( viewVector.z < 0.0)
	{
		vec3 interval = viewVector.xyz * intervalMult;
		vec3 coord = vec3(vtexcoord.st, 1.0);
		coord += noise*interval;

		for (int loopCount = 0;
				(loopCount < MAX_OCCLUSION_POINTS) && (luma(readTexture(coord.st).rgb)/luma(texture2D(texture,lmtexcoord.xy,100).rgb) < coord.p) &&coord.p >= 0.0;
				++loopCount) {
			coord = coord+interval;

		}
		if (coord.t < mincoord) {
			if (readTexture(vec2(coord.s,mincoord)).a == 0.0) {
				coord.t = mincoord;
				discard;
			}
		}
		adjustedTexCoord = mix(fract(coord.st)*vtexcoordam.pq+vtexcoordam.st , adjustedTexCoord , max(dist-MIX_OCCLUSION_DISTANCE,0.0)/(MAX_OCCLUSION_DISTANCE-MIX_OCCLUSION_DISTANCE));
	}
	#endif
	}

	vec4 data0 = texture2DGradARB(texture, adjustedTexCoord.xy,dcdx,dcdy);
  data0.a = texture2DGradARB(texture, adjustedTexCoord.xy,vec2(0.),vec2(0.0)).a;
	if (data0.a > 0.1) data0.a = normalMat.a*0.5+0.5;



	normal = applyBump(tbnMatrix,texture2DGradARB(normals,adjustedTexCoord.xy,dcdx,dcdy).xyz*2.-1.);


	data0.rgb*=color.rgb;
	vec4 data1 = clamp(noise*exp2(-8.)+encode(normal),0.,1.0);

	gl_FragData[0] = vec4(encodeVec2(data0.x,data1.x),encodeVec2(data0.y,data1.y),encodeVec2(data0.z,data1.z),encodeVec2(data1.w,data0.w));



	#else
	vec4 data0 = texture2D(texture, lmtexcoord.xy);

  #ifdef DISABLE_ALPHA_MIPMAPS
  data0.a = texture2DLod(texture,lmtexcoord.xy,0).a;
  #endif

	data0.rgb*=color.rgb;
	if (data0.a > 0.1) data0.a = normalMat.a*0.5+0.5;


	#ifdef MC_NORMAL_MAP
	normal = applyBump(tbnMatrix,texture2D(normals, lmtexcoord.xy).rgb*2.-1.);
	#endif
	vec4 data1 = clamp(noise/256.+encode(normal),0.,1.0);

	gl_FragData[0] = vec4(encodeVec2(data0.x,data1.x),encodeVec2(data0.y,data1.y),encodeVec2(data0.z,data1.z),encodeVec2(data1.w,data0.w));
	#endif


}
