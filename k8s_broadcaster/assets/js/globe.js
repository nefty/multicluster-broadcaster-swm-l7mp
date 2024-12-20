// This code is taken from https://github.com/janarosmonaliev/github-globe
// and slightly adjusted to our needs

import ThreeGlobe from "three-globe";
import * as THREE from "three";
import countries from "./files/globe-data-min.json";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";

function initRenderer() {
  const renderer = new THREE.WebGLRenderer({ antialias: true });
  renderer.setPixelRatio(window.devicePixelRatio);
  renderer.setSize(734, 450);
  return renderer;
}

function initGlobe() {
  const globe = new ThreeGlobe({
    waitForGlobeReady: true,
    animateIn: true,
  })
    .hexPolygonsData(countries.features)
    .hexPolygonResolution(3)
    .hexPolygonMargin(0.7)
    .showAtmosphere(true)
    .atmosphereColor("#3a228a")
    .atmosphereAltitude(0.25)
    .hexPolygonColor((e) => {
      return "rgba(255,255,255, 0.7)";
    });

  globe.rotateY(-Math.PI * (5 / 9));
  globe.rotateZ(-Math.PI / 6);
  const globeMaterial = globe.globeMaterial();
  globeMaterial.color = new THREE.Color(0x3a228a);
  globeMaterial.emissive = new THREE.Color(0x220038);
  globeMaterial.emissiveIntensity = 0.1;
  globeMaterial.shininess = 0.7;
  return globe;
}

function initScene(globe, camera) {
  const scene = new THREE.Scene();
  scene.add(new THREE.AmbientLight(0xbbbbbb, 0.3));
  scene.background = new THREE.Color(0x040d21);
  scene.fog = new THREE.Fog(0x535ef3, 200, 2000);
  scene.add(camera);
  scene.add(globe);
  return scene;
}

function initCamera() {
  const camera = new THREE.PerspectiveCamera();
  camera.aspect = 734 / 450;
  camera.updateProjectionMatrix();

  var dLight = new THREE.DirectionalLight(0xffffff, 10);
  dLight.position.set(-800, 2000, 400);
  camera.add(dLight);

  var dLight1 = new THREE.DirectionalLight(0x7982f6, 5);
  dLight1.position.set(-200, 500, 200);
  camera.add(dLight1);

  var dLight2 = new THREE.PointLight(0x8566cc, 15, 0, 0);
  dLight2.position.set(-200, 500, 200);
  camera.add(dLight2);

  camera.position.z = 300;
  camera.position.x = 0;
  camera.position.y = 0;
  return camera;
}

function initControls(camera, renderer) {
  const controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.dynamicDampingFactor = 0.01;
  controls.enablePan = false;
  controls.minDistance = 200;
  controls.maxDistance = 500;
  controls.rotateSpeed = 0.8;
  controls.zoomSpeed = 1;
  controls.autoRotate = false;

  controls.minPolarAngle = Math.PI / 3.5;
  controls.maxPolarAngle = Math.PI - Math.PI / 3;
  return controls;
}

export class Globe {
  constructor(elementId) {
    this.mouseX = 0;
    this.mouseY = 0;
    this.windowHalfX = window.innerWidth / 2;
    this.windowHalfY = window.innerHeight / 2;
    this.renderer = initRenderer();
    this.globe = initGlobe();
    this.camera = initCamera();
    this.controls = initControls(this.camera, this.renderer);
    this.scene = initScene(this.globe, this.camera);

    document.getElementById(elementId).appendChild(this.renderer.domElement);

    window.addEventListener("resize", () => this.#onWindowResize(), false);
  }

  animate() {
    this.camera.position.x +=
      Math.abs(this.mouseX) <= this.windowHalfX / 2
        ? (this.mouseX / 2 - this.camera.position.x) * 0.005
        : 0;
    this.camera.position.y +=
      (-this.mouseY / 2 - this.camera.position.y) * 0.005;
    this.camera.lookAt(this.scene.position);
    this.controls.update();
    this.renderer.render(this.scene, this.camera);
    requestAnimationFrame(() => this.animate());
  }

  #onWindowResize() {
    this.camera.aspect = 734 / 450;
    this.camera.updateProjectionMatrix();
    this.windowHalfX = 734 / 1.5;
    this.windowHalfY = 734 / 1.5;
    this.renderer.setSize(734, 450);
  }
}
