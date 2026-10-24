# Motor do Forge (bot). O Forge carrega muitas classes por reflexão (IA das
# habilidades, efeitos, preferências em XStream) e o EventBus do Guava chama
# os métodos @Subscribe por reflexão: o R8 não pode cortar nem renomear nada.
-keep class forge.** { *; }
-keep class com.juliocr.edhere.forge.** { *; }
-keep class com.thoughtworks.xstream.** { *; }
-keep class org.tinylog.** { *; }
-keep class org.jgrapht.** { *; }
-keepclassmembers class * {
    @com.google.common.eventbus.Subscribe <methods>;
}
-keepattributes Signature,InnerClasses,EnclosingMethod,*Annotation*

# Partes das bibliotecas que o Forge não usa no Android (rede, desktop, JMX).
-dontwarn **
