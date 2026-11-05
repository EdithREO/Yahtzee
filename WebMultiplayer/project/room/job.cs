using System;
using System.Runtime.InteropServices;
public static class YachtChildJob {
 [StructLayout(LayoutKind.Sequential)] struct Basic { public long a,b; public uint flags; public UIntPtr min,max; public uint count; public UIntPtr affinity; public uint priority,scheduling; }
 [StructLayout(LayoutKind.Sequential)] struct IO { public ulong a,b,c,d,e,f; }
 [StructLayout(LayoutKind.Sequential)] struct Extended { public Basic basic; public IO io; public UIntPtr a,b,c,d; }
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr attributes,string name);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job,int kind,IntPtr info,uint size);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
 [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr handle);
 public static IntPtr Create() {
  IntPtr job=CreateJobObject(IntPtr.Zero,null);
  if(job==IntPtr.Zero) throw new System.ComponentModel.Win32Exception();
  var info=new Extended(); info.basic.flags=0x2000;
  int size=Marshal.SizeOf(info); IntPtr ptr=Marshal.AllocHGlobal(size);
  try { Marshal.StructureToPtr(info,ptr,false); if(!SetInformationJobObject(job,9,ptr,(uint)size)) throw new System.ComponentModel.Win32Exception(); }
  catch {CloseHandle(job);throw;} finally {Marshal.FreeHGlobal(ptr);}
  return job;
 }
 public static void Attach(IntPtr job,IntPtr process) { if(!AssignProcessToJobObject(job,process)) throw new System.ComponentModel.Win32Exception(); }
}
