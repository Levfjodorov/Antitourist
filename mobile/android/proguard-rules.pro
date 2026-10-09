# ML Kit discovers these classes by manifest metadata and constructs them by
# reflection. R8 must retain their names and public no-argument constructors.
-keep class ** implements com.google.firebase.components.ComponentRegistrar {
    public <init>();
}
