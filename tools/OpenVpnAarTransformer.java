import java.io.*;
import java.nio.file.*;
import java.util.jar.*;
import org.objectweb.asm.*;

/** Deterministic patch for the single pinned upstream OpenVPNService class. */
public final class OpenVpnAarTransformer {
    private static final String SERVICE = "de/blinkt/openvpn/core/OpenVPNService";
    private static final String HELPER = "com/forwin/vpn/OpenVpnNotificationActions";
    private static final String SERVICE_ARG = "(L" + SERVICE + ";";

    public static void main(String[] args) throws Exception {
        if (args.length != 2) throw new IllegalArgumentException("usage: input.aar output.aar");
        Path input = Paths.get(args[0]), output = Paths.get(args[1]);
        Files.createDirectories(output.getParent());
        boolean[] touched = new boolean[6];
        try (JarFile jar = new JarFile(input.toFile());
             JarOutputStream out = new JarOutputStream(Files.newOutputStream(output))) {
            java.util.Enumeration<JarEntry> entries = jar.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                byte[] data = jar.getInputStream(entry).readAllBytes();
                if (entry.getName().equals("classes.jar")) data = patchJar(data, touched);
                JarEntry copy = new JarEntry(entry.getName());
                copy.setTime(0L);
                out.putNextEntry(copy); out.write(data); out.closeEntry();
            }
        }
        for (boolean found : touched) {
            if (!found) {
                Files.deleteIfExists(output);
                throw new IllegalStateException("Pinned OpenVPN instrumentation descriptor not found");
            }
        }
    }

    private static byte[] patchJar(byte[] input, boolean[] touched) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        try (JarInputStream in = new JarInputStream(new ByteArrayInputStream(input));
             JarOutputStream out = new JarOutputStream(output)) {
            JarEntry entry;
            while ((entry = in.getNextJarEntry()) != null) {
                byte[] data = in.readAllBytes();
                if (entry.getName().equals(SERVICE + ".class")) data = patchClass(data, touched);
                JarEntry copy = new JarEntry(entry.getName()); copy.setTime(0L);
                out.putNextEntry(copy); out.write(data); out.closeEntry();
            }
        }
        return output.toByteArray();
    }

    private static byte[] patchClass(byte[] input, boolean[] touched) {
        ClassReader reader = new ClassReader(input);
        // Preserve upstream stack-map frames; inserted branches have unchanged
        // locals and an empty stack, explicitly described by F_SAME below.
        ClassWriter writer = new ClassWriter(reader, ClassWriter.COMPUTE_MAXS);
        reader.accept(new ClassVisitor(Opcodes.ASM9, writer) {
            @Override public MethodVisitor visitMethod(int access, String name, String desc,
                                                       String signature, String[] exceptions) {
                MethodVisitor base = super.visitMethod(access, name, desc, signature, exceptions);
                if (name.equals("addVpnActionsToNotification") &&
                        desc.equals("(Landroid/app/Notification$Builder;)V")) {
                    touched[0] = true;
                    return new MethodVisitor(Opcodes.ASM9, base) {
                        @Override public void visitCode() {
                            super.visitCode();
                            super.visitVarInsn(Opcodes.ALOAD, 0);
                            super.visitVarInsn(Opcodes.ALOAD, 1);
                            super.visitMethodInsn(Opcodes.INVOKESTATIC, HELPER, "addActions",
                                    SERVICE_ARG + "Landroid/app/Notification$Builder;)Z", false);
                            Label original = new Label();
                            super.visitJumpInsn(Opcodes.IFEQ, original);
                            super.visitInsn(Opcodes.RETURN);
                            super.visitLabel(original);
                            super.visitFrame(Opcodes.F_SAME, 0, null, 0, null);
                        }
                    };
                }
                if (name.equals("onStartCommand") && desc.equals("(Landroid/content/Intent;II)I")) {
                    touched[1] = true;
                    return new MethodVisitor(Opcodes.ASM9, base) {
                        @Override public void visitCode() {
                            super.visitCode();
                            super.visitVarInsn(Opcodes.ALOAD, 0);
                            super.visitVarInsn(Opcodes.ALOAD, 1);
                            super.visitMethodInsn(Opcodes.INVOKESTATIC, HELPER, "handleReconnect",
                                    SERVICE_ARG + "Landroid/content/Intent;)Z", false);
                            Label original = new Label();
                            super.visitJumpInsn(Opcodes.IFEQ, original);
                            super.visitInsn(Opcodes.ICONST_2); // START_NOT_STICKY, never revive stale intents
                            super.visitInsn(Opcodes.IRETURN);
                            super.visitLabel(original);
                            super.visitFrame(Opcodes.F_SAME, 0, null, 0, null);
                        }
                    };
                }
                if (name.equals("updateState") && desc.equals(
                        "(Ljava/lang/String;Ljava/lang/String;ILde/blinkt/openvpn/core/ConnectionStatus;Landroid/content/Intent;)V")) {
                    touched[2] = true;
                    return new MethodVisitor(Opcodes.ASM9, base) {
                        @Override public void visitCode() {
                            super.visitCode();
                            super.visitVarInsn(Opcodes.ALOAD, 0);
                            super.visitVarInsn(Opcodes.ALOAD, 4);
                            super.visitMethodInsn(Opcodes.INVOKESTATIC, HELPER, "onState",
                                    SERVICE_ARG + "Lde/blinkt/openvpn/core/ConnectionStatus;)V", false);
                        }
                    };
                }
                int hook = name.equals("onDestroy") && desc.equals("()V") ? 3 :
                        name.equals("onRevoke") && desc.equals("()V") ? 4 :
                        name.equals("stopVPN") && desc.equals("(Z)Z") ? 5 : -1;
                if (hook >= 0) {
                    touched[hook] = true;
                    return new MethodVisitor(Opcodes.ASM9, base) {
                        @Override public void visitCode() {
                            super.visitCode();
                            super.visitVarInsn(Opcodes.ALOAD, 0);
                            super.visitMethodInsn(Opcodes.INVOKESTATIC, HELPER, "invalidate",
                                    SERVICE_ARG + ")V", false);
                        }
                    };
                }
                return base;
            }
        }, 0);
        return writer.toByteArray();
    }
}
