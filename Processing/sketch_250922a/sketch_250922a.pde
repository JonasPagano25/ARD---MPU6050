// TCP + STL Processing sketch
// Conectar a localhost:4000 via java.nio.SocketChannel y leer lineas:
// "pitch, roll, yaw\n" (grados). Con esto, se rota el modelo 3D (data/model.stl).

import java.nio.*;
import java.nio.channels.*;
import java.net.*;
import java.nio.charset.*;
import java.util.*;
import java.nio.file.*;

// --- Inicializacion TCP ---
String HOST = "127.0.0.1";
int PORT = 4000;
SocketChannel sc = null;
ByteBuffer bb = ByteBuffer.allocate(4096);
StringBuilder sb = new StringBuilder();

long lastConnectAttempt = 0;
long RECONNECT_INTERVAL_MS = 2000; // Reconexion cada 2 seg

// Angulos (en grados)
float pitch = 0;
float roll  = 0;
float yaw   = 0;

// Setup variables modelo 3D
PShape model;
float modelScale = 1.0;
PVector modelCentroid = new PVector();
float modelRadius = 1.0;

void setup() {
  size(1000, 700, P3D);
  smooth(8);
  rectMode(CENTER);
  noStroke();
  fill(180);
  textSize(14);

  println("Conectandose a" + HOST + ":" + PORT);
  tryConnect(); // initial attempt

  // Carga archivo STL
  try {
    model = loadSTL("ford_ka.stl");
    if (model != null) {
      println("Modelo cargado exitosamente:");
      println("  Centroide: " + modelCentroid);
      println("  Radio: " + modelRadius);
      println("  Escala: " + modelScale);
    }
  } catch (Exception e) {
    println("Falla al cargar STL: " + e);
    model = null;
  }
}

void draw() {
  background(30);
  lights();

  // --- Reconexion ---
  if (sc == null && millis() - lastConnectAttempt > RECONNECT_INTERVAL_MS) {
    tryConnect();
  }
  if (sc != null) {
    pollTCP();
  }

  // --- Optimizacion camara ---
  float fov = PI/3.0f; 
  
  // Distancia de la camara
  float scaledRadius = modelRadius * modelScale;
  float cameraZ = 800.0;
  
  // Mover plano trasero al fondo (evita que el modelo se corte)
  float nearPlane = 1.0;
  float farPlane = 10000.0;
  
  perspective(fov, float(width)/float(height), nearPlane, farPlane);
  
  camera(width/2.0, height/2.0, cameraZ,    
         width/2.0, height/2.0, 0,         
         0, 1, 0);                         

  pushMatrix();
  translate(width/2, height/2, 0);
  
  rotateX(-0.2f);
  
  pushMatrix();
  translate(0, scaledRadius * 1.5, -scaledRadius * 0.5);
  rotateX(HALF_PI);
  fill(40, 40, 60);
  box(scaledRadius * 8, 1, scaledRadius * 8);
  popMatrix();

  // --- Graficado del modelo 3D ---
  if (model != null) {
    pushMatrix();
    
    // Rotaciones
    rotateY(radians(yaw));    // Yaw (eje Y)
    rotateX(radians(pitch));  // Pitch (eje X)
    rotateZ(radians(roll));   // Roll (eje Z)
    
    scale(modelScale);
    
    shape(model);
    popMatrix();
  } else {
    drawAxes(150);
    fill(255);
    textAlign(CENTER);
    text("No se encontro modelo (cargar en sketch/data)", 0, -200);
  }
  
  popMatrix();

  drawHUD(cameraZ);
}

void drawHUD(float cameraZ) {
  hint(DISABLE_DEPTH_TEST);
  camera();
  noLights();
  
  fill(255);
  textAlign(LEFT);
  String status = (sc != null && sc.isConnected()) ? "TCP: CONECTADO" : "TCP: DESCONECTADO";
  text(status + "   pitch: " + nf(pitch, 1, 2) + "°  roll: " + nf(roll, 1, 2) + "°  yaw: " + nf(yaw, 1, 2) + "°", 10, height - 30);
  
  text("Camara Z: " + nf(cameraZ, 1, 1), 10, height - 10);
  
  hint(ENABLE_DEPTH_TEST);
}

/* --- Conexion por Socket a HOST:PORT --- */
void tryConnect() {
  lastConnectAttempt = millis();
  try {
    if (sc != null && sc.isOpen()) {
      sc.close();
    }
    sc = SocketChannel.open();
    sc.configureBlocking(false);
    sc.connect(new InetSocketAddress(HOST, PORT));
    println("SocketChannel creado; intentando conectarse...");
  } catch (Exception e) {
    sc = null;
    println("Conexion fallida: " + e.getMessage());
  }
}

/* --- Lectura info TCP (CMD Arduino) y formateo de bit a caracter--- */
void pollTCP() {
  if (sc == null) return;
  try {
    if (!sc.finishConnect()) {
      return;
    }
    int n = sc.read(bb);
    if (n > 0) {
      bb.flip();
      byte[] b = new byte[bb.remaining()];
      bb.get(b);
      bb.clear();
      sb.append(new String(b, Charset.forName("UTF-8")));
      int idx;
      while ((idx = sb.indexOf("\n")) >= 0) {
        String line = sb.substring(0, idx).trim();
        sb.delete(0, idx + 1);
        if (line.length() > 0) handleLine(line);
      }
    } else if (n == -1) {
      println("TCP: conexion remota cerrada");
      try { sc.close(); } catch (Exception e) {}
      sc = null;
    }
  } catch (Exception e) {
    println("Error lectura TCP: " + e.getMessage());
    try { if (sc != null) sc.close(); } catch (Exception ex) {}
    sc = null;
  }
}

/* --- Lectura variables del puerto TCP ya formateadas --- */
void handleLine(String raw) {
  String[] parts = raw.split(",");
  if (parts.length < 3) {
    println("Linea no simil CSV: '" + raw + "'");
    return;
  }
  try {
    float p = parseFloat(parts[0].trim());
    float r = parseFloat(parts[1].trim());
    float y = parseFloat(parts[2].trim());
    pitch = p;
    roll  = r;
    yaw   = y;
  } catch (Exception e) {
    println("Error en lectura de lineas: '" + raw + "' -> " + e);
  }
}

/* --- Carga STL crudo --- */
PShape loadSTL(String filename) throws Exception {
  String fullPath = dataPath(filename);
  Path path = Paths.get(fullPath);
  if (!Files.exists(path)) {
    println("STL no encontrado en: " + fullPath);
    return null;
  }

  byte[] bytes = Files.readAllBytes(path);
  if (bytes.length < 84) throw new Exception("STL corrupto.");

  String head = new String(bytes, 0, Math.min(80, bytes.length)).trim();
  boolean maybeASCII = head.startsWith("solid");
  if (maybeASCII) {
    String asText = new String(bytes, "UTF-8");
    if (asText.contains("vertex")) {
      return parseASCIISTL(asText);
    } else {
      return parseBinarySTL(bytes);
    }
  } else {
    return parseBinarySTL(bytes);
  }
}

PShape parseASCIISTL(String text) {
  String[] lines = text.split("\\r?\\n");
  ArrayList<PVector> verts = new ArrayList<PVector>();
  ArrayList<PVector> norms = new ArrayList<PVector>();

  PVector currentNormal = new PVector();
  for (String line : lines) {
    line = line.trim();
    if (line.startsWith("facet normal")) {
      String[] tok = line.split("\\s+");
      if (tok.length >= 5) {
        float nx = parseFloat(tok[2]);
        float ny = parseFloat(tok[3]);
        float nz = parseFloat(tok[4]);
        currentNormal = new PVector(nx, ny, nz);
      }
    } else if (line.startsWith("vertex")) {
      String[] tok = line.split("\\s+");
      if (tok.length >= 4) {
        float vx = parseFloat(tok[1]);
        float vy = parseFloat(tok[2]);
        float vz = parseFloat(tok[3]);
        verts.add(new PVector(vx, vy, vz));
        norms.add(currentNormal.copy());
      }
    }
  }
  return buildShapeFromLists(verts, norms);
}

PShape parseBinarySTL(byte[] bytes) {
  ByteBuffer bb2 = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN);
  bb2.position(80);
  int triCount = bb2.getInt();
  ArrayList<PVector> verts = new ArrayList<PVector>();
  ArrayList<PVector> norms = new ArrayList<PVector>();
  for (int i = 0; i < triCount; i++) {
    if (bb2.remaining() < 50) break;
    float nx = bb2.getFloat();
    float ny = bb2.getFloat();
    float nz = bb2.getFloat();
    PVector normal = new PVector(nx, ny, nz);
    for (int v = 0; v < 3; v++) {
      float vx = bb2.getFloat();
      float vy = bb2.getFloat();
      float vz = bb2.getFloat();
      verts.add(new PVector(vx, vy, vz));
      norms.add(normal.copy());
    }
    bb2.getShort();
  }
  return buildShapeFromLists(verts, norms);
}

PShape buildShapeFromLists(ArrayList<PVector> verts, ArrayList<PVector> norms) {
  if (verts.size() == 0) {
    return null;
  }

  PVector minV = new PVector(Float.MAX_VALUE, Float.MAX_VALUE, Float.MAX_VALUE);
  PVector maxV = new PVector(-Float.MAX_VALUE, -Float.MAX_VALUE, -Float.MAX_VALUE);
  PVector sum = new PVector(0, 0, 0);
  
  for (PVector v : verts) {
    sum.add(v);
    minV.x = min(minV.x, v.x);
    minV.y = min(minV.y, v.y);
    minV.z = min(minV.z, v.z);
    maxV.x = max(maxV.x, v.x);
    maxV.y = max(maxV.y, v.y);
    maxV.z = max(maxV.z, v.z);
  }
  
  modelCentroid = PVector.div(sum, verts.size());
  
  float maxDistSq = 0;
  for (PVector v : verts) {
    float distSq = PVector.sub(v, modelCentroid).magSq();
    if (distSq > maxDistSq) maxDistSq = distSq;
  }
  modelRadius = sqrt(maxDistSq);
  
  float targetScreenSize = 250.0;
  modelScale = targetScreenSize / (modelRadius * 2);
  
  println("Parametros del modelo:");
  println("  Bordes: [" + nf(minV.x, 0, 2) + ", " + nf(minV.y, 0, 2) + ", " + nf(minV.z, 0, 2) + "] to [" + 
          nf(maxV.x, 0, 2) + ", " + nf(maxV.y, 0, 2) + ", " + nf(maxV.z, 0, 2) + "]");
  println("  Centroide: [" + nf(modelCentroid.x, 0, 2) + ", " + nf(modelCentroid.y, 0, 2) + ", " + nf(modelCentroid.z, 0, 2) + "]");
  println("  Radio: " + nf(modelRadius, 0, 2));
  println("  Escala: " + nf(modelScale, 0, 6));

  PShape sh = createShape();
  sh.beginShape(TRIANGLES);
  sh.noStroke();
  sh.fill(200, 200, 220);
  sh.ambient(100, 100, 120);
  sh.specular(50);
  sh.shininess(5);
  
  for (int i = 0; i < verts.size(); i++) {
    PVector v = PVector.sub(verts.get(i), modelCentroid);
    PVector n = norms.get(i);
    sh.normal(n.x, n.y, n.z);
    sh.vertex(v.x, v.y, v.z);
  }
  sh.endShape();
  
  return sh;
}

void drawAxes(float len) {
  strokeWeight(3);
  stroke(255, 0, 0); line(0, 0, 0, len, 0, 0); // X - Red
  stroke(0, 255, 0); line(0, 0, 0, 0, len, 0); // Y - Green
  stroke(0, 100, 255); line(0, 0, 0, 0, 0, len); // Z - Blue
  noStroke();
}

/* Limpiar Socket al finalizar */
void exit() {
  try { if (sc != null) sc.close(); } catch (Exception e) {}
  super.exit();
}
