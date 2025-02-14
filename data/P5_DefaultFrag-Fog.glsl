/*
  Porcessing pixel shader by bonjour-lab
  www.bonjour-lab.com
*/
#version 150
#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

uniform vec3 fogColor = vec3(0.9137, 0.9608, 0.9882);
uniform vec3 sunColor = vec3(1.0, 0.9, 0.7);// yellowish
uniform float fogDensity = 0.0005;
uniform float near = 10.0;
uniform float far = 400.0;
uniform vec3 sunDir;
uniform vec2 mouse;

uniform bool textureMode;

//constant
const float zero_float = 0.0;
const float one_float = 1.0;
const vec3 zero_vec3 = vec3(0.0);
const vec3 minus_one_vec3 = vec3(0.0-1.0);

//Light component (max 8)
uniform int lightCount;
uniform vec4 lightPosition[8];
uniform vec3 lightNormal[8];
uniform vec3 lightAmbient[8];
uniform vec3 lightDiffuse[8];
uniform vec3 lightSpecular[8];
uniform vec3 lightFalloff[8];
uniform vec2 lightSpot[8];

uniform sampler2D shadowMap;


uniform sampler2D texture;
uniform vec2 texOffset;

in vec4 vertColor;
in vec4 backVertColor;
in vec4 vertTexCoord;
in vec3 ecNormal;
in vec4 ecVertex;

//Material attribute
in vec4 vambient;
in vec4 vspecular;
in vec4 vemissive;
in float vshininess;



out vec4 fragColor;


float fallOffFactor(vec3 lightPos, vec3 ecVertex, vec3 coeff){
  vec3 lpv = lightPos - ecVertex;
  vec3 dist = vec3(one_float);
  dist.z = dot(lpv, lpv);
  dist.y = sqrt(dist.z);
  return one_float / dot(dist, coeff);
}

float spotFactor(vec3 lightPos, vec3 ecVertex, vec3 lightNormal, float minCos, float spotExp){
  vec3 lpv = normalize(lightPos - ecVertex);
  vec3 nln = minus_one_vec3 * lightNormal;
  float spotCos = dot(nln, lpv);
  return spotCos <= minCos ? zero_float : pow(spotCos, spotExp);

}

float diffuseFactor(vec3 lightDir, vec3 ecNormal){
  vec3 s = normalize(lightDir);
  vec3 n = normalize(ecNormal);
  return max(0.0, dot(s, n));
}

float specularFactor(vec3 lightDir, vec3 ecVertex, vec3 ecNormal, float shininess){
  vec3 s = normalize(lightDir);
  vec3 n = normalize(ecNormal);
  vec3 v = normalize(-ecVertex);
  vec3 r = reflect(-s, n);
  return pow(max(dot(r, v), 0.0), shininess);
}

void main() {
  //PREPROCESSOR TEST FOR TEXTURE TEST → Check if P5 can write a define
  vec4 texColor = vec4(1.0);
  if(textureMode){
    texColor = texture2D(texture, vertTexCoord.st);
  }



  //Light computation
  vec3 totalAmbient = vec3(1.0);
  vec3 totalFrontDiffuse = vec3(0.0);
  vec3 totalBackDiffuse = vec3(0.0);
  vec3 totalFrontSpecular = vec3(0.0);
  vec3 totalBackSpecular = vec3(0.0);

  for(int i=0; i<8; i++){
    if(i == lightCount) break;
    vec3 lightPos = lightPosition[i].xyz;
    bool isDir = lightPosition[i].w < one_float;
    float spotCos = lightSpot[i].x;
    float spotExp = lightSpot[i].y;

    vec3 lightDir;
    float fallOff;
    float spotf;

    if(isDir){
      fallOff = one_float;
      lightDir = minus_one_vec3 * lightNormal[i];
    }else{
      fallOff = fallOffFactor(lightPos, ecVertex.xyz, lightFalloff[i]);
      lightDir = normalize(lightPos - ecVertex.xyz);
    }

    spotf = spotExp > zero_float ? spotFactor(lightPos, ecVertex.xyz, lightNormal[i], spotCos, spotExp) : one_float;
    
    //define Ambient
    if(any(greaterThan(lightAmbient[i], zero_vec3))){
      totalAmbient = lightAmbient[i] * fallOff;
      //totalAmbient += lightAmbient[i] * fallOff;
    }

    //Define Diffuse
    if(any(greaterThan(lightDiffuse[i], zero_vec3))){
      totalFrontDiffuse += lightDiffuse[i] * fallOff * spotf * diffuseFactor(lightDir, ecNormal);
      totalBackDiffuse += lightDiffuse[i] * fallOff * spotf * diffuseFactor(lightDir, ecNormal * minus_one_vec3);
    }
    
    //Define Specular
    if(any(greaterThan(lightSpecular[i], zero_vec3))){
      totalFrontSpecular += lightSpecular[i] * fallOff * spotf * specularFactor(lightDir, ecVertex.xyz, ecNormal, vshininess);
      totalBackSpecular += lightSpecular[i] * fallOff * spotf * specularFactor(lightDir, ecVertex.xyz, ecNormal * minus_one_vec3, vshininess);
    }
  }

 
  

  vec4 AlbedoFront = vec4(totalAmbient, 0.0) * vambient +
                     vec4(totalFrontDiffuse, 0.0) * vertColor +
                     vec4(totalFrontSpecular, 1.0) * vspecular +
                     vec4(vemissive.rgb, 0.0);

  vec4 AlbedoBack = vec4(totalAmbient, 0.0) * vambient +
                    vec4(totalBackDiffuse, 1.0) * vertColor +
                    vec4(totalBackSpecular, 0.0) * vspecular +
                    vec4(vemissive.rgb, 0.0);

                     /*FOG*/
  float dist = length(ecVertex);
  float fogFactor;
  float sunAmount = max(dot(normalize(ecVertex.xyz), sunDir.xyz), 0.0);
  vec3 scatteringSun = mix(fogColor, sunColor, pow(sunAmount, 8.0));
  vec3 finalColor;

    if(FOGTYPE == 0){ //linear
      fogFactor = (far - dist) / (far - near);
      fogFactor = clamp(fogFactor, 0.0, 1.0);

      finalColor = mix(scatteringSun, AlbedoFront.rgb * texColor.rgb, fogFactor);
    }else if(FOGTYPE == 1){//exponential
      fogFactor = exp(-dist * fogDensity);
      fogFactor = clamp(fogFactor, 0.0, 1.0);

      finalColor = mix(scatteringSun, AlbedoFront.rgb * texColor.rgb, fogFactor);
    }else if(FOGTYPE == 2){
      float be = 0.0025; //extinction
      float bi = 0.002; //inscattring
      float ext = exp(-dist * be);
      float insc = exp(-dist * bi);
      finalColor = AlbedoFront.rgb * texColor.rgb * (ext) + scatteringSun * (1.0 - insc);
    }


  fragColor = vec4(finalColor, 1.0);//texColor * (gl_FrontFacing ? AlbedoFront : AlbedoBack);
}