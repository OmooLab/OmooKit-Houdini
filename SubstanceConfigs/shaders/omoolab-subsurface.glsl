//- Import from libraries.
import lib-pbr.glsl
import lib-pbr-aniso.glsl
import lib-bent-normal.glsl
import lib-coat.glsl
import lib-sheen.glsl
import lib-utils.glsl


vec3 rgb2hsv(vec3 c)
{
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

//- Rewrite lib-sss.glsl
//- ---------------------------------------

const float DEFAULT_Subsurface_ANISOTROPY = 0.5; 

//: param auto channel_scatteringcolor
uniform SamplerSparse subsurfaceradius_tex;

// Use user0 as Subsurface anisotropy
//: param auto channel_user0
uniform SamplerSparse subsurface_anisotropy_tex;

//: param custom {
//:   "group": "Subsurface",
//:   "label": "Enable",
//:   "default": true,
//:   "description": "<html><head/><body><p>Enable the Subsurface Scattering.</p></body></html>",
//:   "asm": "scatter"
//: }
uniform_specialization bool subsurfaceEnabled;

//: param custom {
//:   "group": "Subsurface",
//:   "label": "Scale",
//:   "default": 1,
//:   "min": 0,
//:   "max": 10.0,
//:   "description": "<html><head/><body><p>Controls the subsurface radius scale.</p></body></html>",
//:   "visible": "input.sssEnabled",
//:   "asm": "scatter_distance"
//: }
uniform float subsurfaceScale;

// Read sss anisotropy
float getSubsurfaceAnisotropy(vec4 sampledValue) 
{ 
  return sampledValue.r + DEFAULT_Subsurface_ANISOTROPY * (1.0 - sampledValue.g); 
}
float getSubsurfaceAnisotropy(SamplerSparse sampler, SparseCoord coord) 
{ 
  return getSubsurfaceAnisotropy(textureSparse(sampler, coord)); 
}

vec4 getSubsurfaceCoefficients(vec3 subsurfaceRadius) {
	vec4 coeffs = vec4(0.0);
	if (subsurfaceEnabled) {
		coeffs.xyz = subsurfaceScale * subsurfaceRadius;
		coeffs.w = coeffs.xyz==vec3(0.0) ? 0.0 : 1.0;
		coeffs.xyz *= vec3(1.0);
	}
	return coeffs;
}

vec4 getSubsurfaceCoefficients(SparseCoord coord) {
	if (subsurfaceEnabled) {
		float sss_anisotropy = 2 * getSubsurfaceAnisotropy(subsurface_anisotropy_tex, coord);
		return sss_anisotropy * getSubsurfaceCoefficients(getScatteringPerComponent(subsurfaceradius_tex, coord));
	}
	return vec4(0.0);
}

vec4 getSubsurfaceColor(vec3 color, float weight) {
	return vec4(color,weight);
}

vec4 getSubsurfaceColor() {
	if (subsurfaceEnabled) {
		return getSubsurfaceColor(vec3(0.0),1);
	}
	return vec4(0.0);
}

float getSubsurfaceWeight(vec4 coeffs)
{
  return (coeffs.r+coeffs.g+coeffs.b)/3;
}


// ---------------------------------------Shader----------------------------------------------
// OmooLab Subsurface Shader
//: metadata {
//:   "mdl":"mdl::alg::materials::painter::standard"
//: }

//- Show back faces as there may be holes in front faces.
//: state cull_face off

// sss only work with "opaque"
//- Enable alpha blending
//: state blend none

//- Channels needed for metal/rough workflow are bound here.
//: param auto channel_basecolor
uniform SamplerSparse basecolor_tex;
//: param auto channel_roughness
uniform SamplerSparse roughness_tex;
//: param auto channel_metallic
uniform SamplerSparse metallic_tex;
//: param auto channel_anisotropylevel
uniform SamplerSparse anisotropylevel_tex;
//: param auto channel_anisotropyangle
uniform SamplerSparse anisotropyangle_tex;
//: param auto channel_specularlevel
uniform SamplerSparse specularlevel_tex;
//: param auto channel_specularedgecolor
uniform SamplerSparse specularedgecolor_tex;

//: param custom {
//:   "group": "Specular",
//:   "label": "Enable anisotropy",
//:   "default": true,
//:   "asm": "anisotropy",
//:   "description": "<html><head/><body><p>Allows reflections to stretch in
//:   one direction along the surface.</p></body></html>"
//: }
uniform_specialization bool anisotropyEnabled;
//: param custom {
//:   "group": "Specular",
//:   "label": "Index of refraction",
//:   "min": 0.0,
//:   "max": 40.0,
//:   "default": 1.5,
//:   "asm": "specular_ior",
//:   "description": "<html><head/><body><p>The amount light bends as it passes
//:   through the object.</p></body></html>"
//: }
uniform float specularIoR;
//: param custom {
//:   "group": "Specular",
//:   "label": "Enable edge color",
//:   "default": true,
//:   "asm": "specular_edge_color",
//:   "description": "<html><head/><body><p>Allows to specify the color of
//:   light reflections. Affects glancing angles for metallic materials.</p>
//:   </body></html>"
//: }
uniform_specialization bool specularEdgeColorEnabled;


//- Shader entry point.
void shade(V2F inputs)
{
	// // Apply parallax occlusion mapping if possible
	// vec3 viewTS = worldSpaceToTangentSpace(getEyeVec(inputs.position), inputs);
	// applyParallaxOffset(inputs, viewTS);

	// Fetch material parameters, and conversion to the specular/roughness model
	float baseRoughness = getRoughness(roughness_tex, inputs.sparse_coord);

	float anisotropyLevel = 0.0;
	float anisotropyAngle = 0.0;
	if (anisotropyEnabled) {
		anisotropyLevel = getAnisotropyLevel(anisotropylevel_tex, inputs.sparse_coord);
		if (anisotropyLevel > 0.0) {
			anisotropyAngle = getAnisotropyAngle(anisotropyangle_tex, inputs.sparse_coord);
		}
	}

	
	vec4 subsurfaceCoefficients = getSubsurfaceCoefficients(inputs.sparse_coord);
	float subsurfaceWeight = getSubsurfaceWeight(subsurfaceCoefficients);

	vec3 subsurfaceCoefficientsHSV = rgb2hsv(subsurfaceCoefficients.rgb);
	subsurfaceCoefficientsHSV.g = clamp(subsurfaceCoefficientsHSV.g * 1.5, 0, 1);
	subsurfaceCoefficients = vec4(hsv2rgb(subsurfaceCoefficientsHSV),1.0);
	
	vec3 baseColor = getBaseColor(basecolor_tex, inputs.sparse_coord);
	vec4 subsurfaceColor = getSubsurfaceColor();

	baseColor = (1 - subsurfaceWeight * 0.1) * baseColor + subsurfaceWeight * 0.1 * vec3(1.0);

	float metallic = getMetallic(metallic_tex, inputs.sparse_coord);
	vec3 diffColor = generateDiffuseColor(baseColor, metallic);
	float specularLevel = getSpecularLevel(specularlevel_tex, inputs.sparse_coord);
	
	// Use spec Color
	vec3 specColor_metal = baseColor;
	float dielectricF0 = iorToSpecularLevel(1.0, specularIoR);
	float coatOpacity = 0.0;
	if (coatEnabled) {
		coatOpacity = getCoatOpacity(coatOpacity_tex, inputs.sparse_coord);
		if (coatOpacity > 0.0) {
			float underCoatF0 = iorToSpecularLevel(coatIoR, specularIoR);
			dielectricF0 = mix(dielectricF0, underCoatF0, coatOpacity);
		}
	}
	vec3 specColor_dielectric = vec3(dielectricF0 * 2.0 * specularLevel);

	// Get detail (ambient occlusion) and global (shadow) occlusion factors
	// separately in order to blend the bent normals properly
	float shadowFactor = getShadowFactor();
	float occlusion = getAO(inputs.sparse_coord, true, use_bent_normal);

	float specOcclusion = specularOcclusionCorrection(
		use_bent_normal ? shadowFactor : occlusion * shadowFactor,
		metallic,
		baseRoughness);

	vec3 normal = computeWSNormal(inputs.sparse_coord,
		inputs.tangent, inputs.bitangent, inputs.normal);
	LocalVectors vectors = computeLocalFrame(inputs, normal, anisotropyAngle);
	computeBentNormal(vectors,inputs);

	// Diffuse lobe:
	vec3 diffuseShading = occlusion * shadowFactor * envIrradiance(getDiffuseBentNormal(vectors));

	// Specular lobes:
	// The specs can be interpreted as interpolating between two lobes.
	// However, due to the prohibitive cost for real-time, we interpolate
	// between two specular colors and use it for a single specular lobe.
	vec3 specColor = mix(specColor_dielectric, specColor_metal, metallic);
	vec3 specSecondaryColor = vec3(1.0);

	if (specularEdgeColorEnabled) {
		specSecondaryColor = getSpecularEdgeColor(specularedgecolor_tex, inputs.sparse_coord);
	}

	vec3 specEdgeColor = mix(vec3(1.0), specSecondaryColor, metallic);
	vec3 specColoring = mix(vec3(1.0), specSecondaryColor, 1.0 - metallic);
	vec3 specReflection = vec3(0.0);
	if (anisotropyEnabled) {
		vec2 roughnessAniso = generateAnisotropicRoughnessASM(baseRoughness, anisotropyLevel);
		specReflection = pbrComputeSpecularAnisotropic(
			vectors,
			specColor,
			specEdgeColor,
			roughnessAniso,
			occlusion,
			getBentNormalSpecularAmount());
	}
	else {
		specReflection = pbrComputeSpecular(
			vectors,
			specColor,
			specEdgeColor,
			baseRoughness,
			occlusion,
			getBentNormalSpecularAmount());
	}
	vec3 specularShading = specOcclusion * specColoring * specReflection;

	// Sheen:
	if (sheenEnabled) {
		float sheenOpacity = getSheenOpacity(sheenOpacity_tex, inputs.sparse_coord);
		if (sheenOpacity > 0.0) {
			float sheenRoughness = getSheenRoughness(sheenRoughness_tex, inputs.sparse_coord);
			vec3 sheenColor = sheenOpacity * getSheenColor(sheenColor_tex, inputs.sparse_coord);
			vec3 sheenSpecularShading = pbrComputeSheen(vectors, sheenColor, sheenRoughness);
			specularShading += specOcclusion * sheenSpecularShading;
		}
	}

	// Coating:
	if (coatOpacity > 0.0) {
		vec3 coatNormal = getWSCoatNormal(inputs.sparse_coord,
			inputs.tangent, inputs.bitangent, inputs.normal);
		LocalVectors coatVectors = computeLocalFrame(inputs, coatNormal, 0.0);

		vec3 coatColor = getCoatColor(coatColor_tex, inputs.sparse_coord);
		// float coatSpecularLevel = getCoatSpecularLevel(coatSpecularLevel_tex, inputs.sparse_coord);
		float coatSpecularLevel = 1;
		vec3 coatSpecColor = vec3(iorToSpecularLevel(1.0, coatIoR) * 2.0 * coatSpecularLevel);

		float coatRoughness = getCoatRoughness(coatRoughness_tex, inputs.sparse_coord);
		float coatSpecOcclusion = specularOcclusionCorrection(occlusion * shadowFactor, 0.0, coatRoughness);
		vec3 coatSpecularShading = pbrComputeSpecular(coatVectors, coatSpecColor, coatRoughness);

		float ndv = clamp(dot(coatVectors.normal, vectors.eye), 1e-4, 1.0);
		vec3 coatAbsorption = coatPassageColorMultiplier(coatColor, coatOpacity, ndv);
		coatAbsorption *= coatAbsorption;

		diffuseShading *= coatAbsorption;
		specularShading *= coatAbsorption;
		specularShading += (coatSpecOcclusion * coatOpacity) * coatSpecularShading;
	}

	albedoOutput(diffColor);
	emissiveColorOutput(pbrComputeEmissive(emissive_tex, inputs.sparse_coord));
	diffuseShadingOutput(diffuseShading);
	specularShadingOutput(specularShading);

	sssCoefficientsOutput(subsurfaceCoefficients);
	sssColorOutput(subsurfaceColor);

	alphaOutput(1);
}
