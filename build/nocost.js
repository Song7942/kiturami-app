/* 호스팅판에서만 — 가격정보의 '원가' 열을 통째로 뺀다.
 *   앱 본체는 건드리지 않고, 표를 다 그린 뒤 그 열만 걷어낸다.
 *   가격정보는 머리글 표와 본문 표가 따로이므로 둘 다 손본다.
 *   머리글 글자로 찾으므로 열 차례가 바뀌어도 따라간다(한국어·러시아어 둘 다).
 */
(function(){
  var COST=/^(원가|Себестоимость)$/;
  var CARD=/^(원가|Себестоимость)\b/;

  // 머리글 첫 줄에서 '원가' 묶음이 몇 번째 열부터 몇 칸인지
  function findCost(head){
    if(!head || !head.rows.length) return null;
    var r0=head.rows[0], col=0, i;
    for(i=0;i<r0.cells.length;i++){
      var th=r0.cells[i], span=th.colSpan||1;
      if(COST.test((th.textContent||'').trim())) return { start:col, len:span, cell:th };
      col+=span;
    }
    return null;
  }

  // 머리글 둘째 줄의 칸이 실제로 몇 번째 열인지 (위 줄에서 rowspan 으로 내려온 자리는 건너뛴다)
  function row1Cols(head){
    if(head.rows.length<2) return [];
    var r0=head.rows[0], covered={}, col=0, i, k;
    for(i=0;i<r0.cells.length;i++){
      var th=r0.cells[i], span=th.colSpan||1;
      if((th.rowSpan||1)>1){ for(k=0;k<span;k++) covered[col+k]=1; }
      col+=span;
    }
    var out=[], c=0;
    for(i=0;i<head.rows[1].cells.length;i++){
      while(covered[c]) c++;
      out.push(c); c++;
    }
    return out;
  }

  // 한 표에서 그 자리의 열을 걷어낸다(본문 줄 + colgroup)
  function cutTable(tbl, start, len){
    var b, r, j;
    var bodies=tbl.tBodies;
    for(b=0;b<bodies.length;b++){
      for(r=0;r<bodies[b].rows.length;r++){
        var tr=bodies[b].rows[r];
        if(tr.cells.length < start+len) continue;         // 안내 줄 등 칸 수가 다른 줄은 둔다
        for(j=len-1;j>=0;j--) tr.deleteCell(start+j);
      }
    }
    var cg=tbl.querySelectorAll('colgroup');
    for(b=0;b<cg.length;b++){
      var cols=cg[b].children;
      if(cols.length < start+len) continue;
      for(j=len-1;j>=0;j--) cg[b].removeChild(cols[start+j]);
    }
  }

  function sweep(){
    var pane=document.getElementById('pane-price'); if(!pane) return;
    var tabs=pane.querySelectorAll('table'), i;
    var head=null, hit=null;
    for(i=0;i<tabs.length && !hit;i++){
      if(!tabs[i].tHead) continue;
      var h=findCost(tabs[i].tHead);
      if(h){ head=tabs[i].tHead; hit=h; }
    }
    if(!hit) return;                                      // 이미 걷어냈거나 그런 표가 없다
    // 머리글 둘째 줄 → 첫 줄 차례로 지운다
    var map=row1Cols(head);
    if(head.rows.length>1){
      for(i=map.length-1;i>=0;i--){
        if(map[i]>=hit.start && map[i]<hit.start+hit.len) head.rows[1].deleteCell(i);
      }
    }
    hit.cell.parentNode.removeChild(hit.cell);
    // 머리글 표·본문 표 모두에서 그 열을 걷어낸다
    for(i=0;i<tabs.length;i++) cutTable(tabs[i], hit.start, hit.len);
    // 모바일 카드: '원가' 로 시작하는 줄을 숨긴다
    var rows=pane.querySelectorAll('.order-card div');
    for(i=0;i<rows.length;i++){
      var sp=rows[i].firstElementChild;
      if(sp && CARD.test((sp.textContent||'').trim())) rows[i].style.display='none';
    }
  }

  function later(){ setTimeout(sweep,0); setTimeout(sweep,250); }

  function hook(name){
    var f=window[name]; if(typeof f!=='function') return;
    window[name]=function(){ var r=f.apply(this, arguments); try{ later(); }catch(e){} return r; };
  }
  function install(){
    ['renderPriceCalc','renderPriceRegion','renderPriceCompany','renderPriceSupply','renderPriceActive',
     'switchPriceView','loadPriceTab'].forEach(hook);
    // 엑셀 내려받기에서도 '원가' 열을 뺀다.
    //   머리글이 맨 윗줄이 아니라 몇 줄 밑에 있을 수 있어 앞쪽 여덟 줄을 훑는다.
    //   '원가' 는 여러 칸을 합쳐 놓은 머리글이라, 바로 뒤의 빈 칸까지 한 묶음으로 본다.
    if(window.XLSX && XLSX.utils && !XLSX.utils.__noCost){
      var mk=XLSX.utils.aoa_to_sheet;
      XLSX.utils.aoa_to_sheet=function(aoa, opts){
        try{
          var RE=/원가|Себестоимость/, at=-1, row=null, i;
          for(i=0;i<Math.min(8,(aoa||[]).length);i++){
            var r=aoa[i]; if(!r || !r.some) continue;
            var j=r.findIndex(function(h){ return RE.test(String(h==null?'':h)); });
            if(j>=0){ at=j; row=r; break; }
          }
          if(at>=0){
            var len=1;
            while(at+len<row.length && String(row[at+len]==null?'':row[at+len]).trim()==='') len++;
            aoa=aoa.map(function(x){ var y=(x||[]).slice(); y.splice(at, len); return y; });
          }
        }catch(e){}
        return mk.call(this, aoa, opts);
      };
      XLSX.utils.__noCost=1;
    }
    setTimeout(sweep, 400);
  }
  if(document.readyState==='complete'||document.readyState==='interactive') setTimeout(install,0);
  else window.addEventListener('DOMContentLoaded', install);
})();
