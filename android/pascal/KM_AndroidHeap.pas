unit KM_AndroidHeap;
{$mode delphi}
// Amortized growth for large reallocations, like Delphi's FastMM does.
// FPC's default heap on Android reallocates large blocks with mmap/copy/munmap on every resize,
// which makes code that grows strings/arrays step by step quadratic (e.g. the PascalScript compiler
// appends bytecode one byte at a time: a big mission script took minutes to compile).
// Must be the first unit after cthreads in the library uses clause.
interface

implementation

const
  BIG_BLOCK = 64 * 1024; // smaller blocks are handled well by the FPC heap itself

var
  gOldMM: TMemoryManager;


function AmortizedReAllocMem(var p: Pointer; aSize: PtrUInt): Pointer;
var
  cur, alloc: PtrUInt;
  np: Pointer;
begin
  if (p = nil) or (aSize < BIG_BLOCK) then
    Exit(gOldMM.ReAllocMem(p, aSize));

  cur := gOldMM.MemSize(p);
  // Grow: reserve 25% more so that following small grows don't move the block again
  if aSize > cur then
  begin
    alloc := aSize + aSize div 4;
    np := gOldMM.GetMem(alloc);
    if np = nil then
      Exit(gOldMM.ReAllocMem(p, aSize));
    Move(p^, np^, cur);
    gOldMM.FreeMem(p);
    p := np;
    Exit(p);
  end;

  // Shrink a lot: give memory back. Small shrink: keep the block as is
  if aSize < cur div 2 then
    Exit(gOldMM.ReAllocMem(p, aSize));

  Result := p;
end;


procedure Install;
var
  mm: TMemoryManager;
begin
  GetMemoryManager(gOldMM);
  mm := gOldMM;
  mm.ReAllocMem := AmortizedReAllocMem;
  SetMemoryManager(mm);
end;


initialization
  Install;

end.
