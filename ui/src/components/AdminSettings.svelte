<script lang="ts">
  import { ADMIN_OPEN, ADMIN_PAYLOAD, CREATED_ZONE, OVERLAY_OPEN } from '@store/stores';
  import { SendNUI } from '@utils/SendNUI';
  import { fade, scale } from 'svelte/transition';
  import { onMount } from 'svelte';

  let config: any = null;
  let tab = 'general';
  let saving = false;
  let status = '';
  let statusType = '';
  let advanced = '';
  let zoneName = 'Área sem despacho';
  let pendingShape = '';
  let lastPayload: any = null;
  let lastCreated: any = null;
  let editingIndex = -1;
  let pendingIndex = -1;
  let zoneDraft: any = null;
  let geometryText = '';
  let debugState: any = { mode: 'off', selected: {} };
  let debugBusy = false;
  const clone = (value: any) => JSON.parse(JSON.stringify(value || {}));

  onMount(() => {
    const receive = (event: MessageEvent) => {
      if (event.data?.action === 'zoneDebugState') debugState = event.data.data;
    };
    window.addEventListener('message', receive);
    SendNUI('getDispatchZoneDebug').then((state: any) => { if (state?.mode) debugState = state; });
    return () => window.removeEventListener('message', receive);
  });

  $: OVERLAY_OPEN.set($ADMIN_OPEN);
  $: if ($ADMIN_OPEN && $ADMIN_PAYLOAD !== lastPayload) {
    lastPayload = $ADMIN_PAYLOAD;
    config = clone($ADMIN_PAYLOAD?.config);
    zoneDraft = null;
    editingIndex = -1;
    ensureShape();
    advanced = JSON.stringify(config, null, 2);
  }
  $: if ($CREATED_ZONE && $CREATED_ZONE !== lastCreated) {
    lastCreated = $CREATED_ZONE;
    if (pendingShape) {
      const created = $CREATED_ZONE.value;
      if (created && config) {
        const list = config.Locations.NoDispatchZones;
        if (pendingIndex >= 0 && zoneDraft && editingIndex === pendingIndex) {
          zoneDraft = { ...zoneDraft, ...created };
          geometryText = JSON.stringify(created.points || [], null, 2);
          status = 'Geometria ajustada. Aplique a edição e salve para publicar.';
        } else if (pendingIndex < 0) {
          list.push({
            ...created,
            id: `dispatch-${Date.now()}`,
            label: zoneName.trim() || 'Área sem despacho',
            active: true,
          });
          status = 'Área adicionada. Clique em Salvar para publicar.';
        }
        // Reassign the root so Svelte refreshes the keyed zone list as soon
        // as the world editor returns. Mutating the nested array alone is not
        // observable by the compiled component.
        config = { ...config };
        statusType = 'success';
        advanced = JSON.stringify(config, null, 2);
      } else {
        status = 'Editor cancelado. A geometria anterior foi mantida.';
        statusType = 'error';
      }
      pendingShape = '';
      pendingIndex = -1;
    }
  }

  function ensureShape() {
    if (!config.Locations) config.Locations = {};
    if (!Array.isArray(config.Locations.NoDispatchZones)) config.Locations.NoDispatchZones = [];
    if (!Array.isArray(config.Locations.HuntingZones)) config.Locations.HuntingZones = [];
    if (!config.SafeZoneIntegration) config.SafeZoneIntegration = { Enabled: false, Resource: 'forge-smallresources', IncludeTypes: { safezone: true } };
    if (!config.SafeZoneIntegration.IncludeTypes) config.SafeZoneIntegration.IncludeTypes = { safezone: true };
  }

  $: jobOptions = (() => {
    const listed = Array.isArray($ADMIN_PAYLOAD?.jobs) ? $ADMIN_PAYLOAD.jobs : [];
    const known = new Set(listed.map((job: any) => job.name));
    const preserved = (config?.Jobs || [])
      .filter((name: string) => !known.has(name))
      .map((name: string) => ({ name, label: name, type: 'categoria configurada' }));
    return [...listed, ...preserved];
  })();

  function toggleJob(name: string) {
    const selected = new Set(Array.isArray(config.Jobs) ? config.Jobs : []);
    selected.has(name) ? selected.delete(name) : selected.add(name);
    config.Jobs = Array.from(selected);
    config = { ...config };
    advanced = JSON.stringify(config, null, 2);
  }
  function numeric(key: string, value: string) { config[key] = Number(value); }

  async function createZone(shape: string, editing = false) {
    pendingShape = shape;
    pendingIndex = editing ? editingIndex : -1;
    status = 'Use o editor 3D e pressione Enter para salvar a geometria.';
    statusType = '';
    const response: any = await SendNUI('createDispatchZone', {
      shape,
      radius: editing ? zoneDraft.radius || 20 : 20,
      thickness: editing ? zoneDraft.thickness || 4 : 4,
    }).catch(() => ({ ok: false, error: 'Falha de comunicação ao abrir o editor.' }));
    if (!response?.ok) {
      pendingShape = '';
      pendingIndex = -1;
      status = response?.error || 'Não foi possível abrir o editor.';
      statusType = 'error';
    }
  }

  function removeZone(index: number) {
    zoneDraft = null;
    editingIndex = -1;
    config.Locations.NoDispatchZones.splice(index, 1);
    config = { ...config };
    advanced = JSON.stringify(config, null, 2);
  }

  const zoneId = (zone: any, index: number) => String(zone.id || `no-dispatch:${index + 1}`);
  const debugVisible = (zone: any, index: number) => zone.active !== false &&
    (debugState.mode === 'all' || (debugState.mode === 'individual' && debugState.selected?.[`no_dispatch:${zoneId(zone, index)}`] === true));

  async function teleportZone(zone: any, index: number) {
    const response: any = await SendNUI('teleportDispatchZone', { id: zoneId(zone, index) })
      .catch(() => ({ ok: false, error: 'Falha de comunicação ao teleportar.' }));
    status = response?.ok ? 'Teleportado para o centro da área publicada.' : response?.error || 'Não foi possível teleportar.';
    statusType = response?.ok ? 'success' : 'error';
  }

  async function toggleDebug(zone: any, index: number) {
    debugBusy = true;
    const response: any = await SendNUI('toggleDispatchZoneDebug', { id: zoneId(zone, index), enabled: !debugVisible(zone, index) })
      .catch(() => ({ ok: false, error: 'Falha de comunicação ao alterar a depuração.' }));
    debugBusy = false;
    status = response?.ok ? 'Depuração atualizada somente para você. Ocultar todas no Forge também desliga esta seleção.' : response?.error || 'Não foi possível alterar a depuração.';
    statusType = response?.ok ? 'success' : 'error';
  }

  function editZone(zone: any, index: number) {
    editingIndex = index;
    zoneDraft = clone(zone);
    zoneDraft.shape ||= zone.radius ? 'sphere' : 'box';
    zoneDraft.label ||= zone.name || 'Área sem despacho';
    if (zoneDraft.shape === 'box') {
      zoneDraft.height ??= zone.maxZ != null && zone.minZ != null ? Math.max(.5, zone.maxZ - zone.minZ) : 4;
      zoneDraft.heading ??= zone.rotation || 0;
      zoneDraft.length ??= zone.size?.x || 10;
      zoneDraft.width ??= zone.size?.y || 10;
    }
    geometryText = JSON.stringify(zone.points || [], null, 2);
    status = 'Edite os dados ou redesenhe a área. As alterações só entram no mundo após Salvar e publicar.';
    statusType = '';
  }

  function applyZoneEdit() {
    try {
      const draft = clone(zoneDraft);
      if (!String(draft.label || '').trim()) throw new Error('Informe o nome da área.');
      if (draft.shape === 'poly') {
        const points = JSON.parse(geometryText);
        if (!Array.isArray(points) || points.length < 3 || points.length > 64 || points.some((p: any) =>
          !p || ['x', 'y', 'z'].some(key => typeof p[key] !== 'number' || !Number.isFinite(p[key])))) throw new Error('Informe de 3 a 64 pontos com x, y e z numéricos.');
        draft.points = points;
        draft.coords = Object.fromEntries(['x', 'y', 'z'].map(key => [key, points.reduce((sum: number, point: any) => sum + point[key], 0) / points.length]));
        if (!(draft.thickness >= .5 && draft.thickness <= 1000)) throw new Error('A altura deve estar entre 0,5 e 1000 metros.');
      } else {
        if (['x', 'y', 'z'].some(key => typeof draft.coords?.[key] !== 'number' || !Number.isFinite(draft.coords[key]))) throw new Error('Coordenadas inválidas.');
        if (draft.shape === 'sphere' && !(draft.radius >= .5 && draft.radius <= 2000)) throw new Error('O raio deve estar entre 0,5 e 2000 metros.');
        if (draft.shape === 'box') {
          if (![draft.length, draft.width].every(value => value >= .5 && value <= 2000) || !(draft.height >= .5 && draft.height <= 1000) || !Number.isFinite(draft.heading)) throw new Error('Dimensões ou direção inválidas.');
          draft.minZ = draft.coords.z - draft.height / 2;
          draft.maxZ = draft.coords.z + draft.height / 2;
        }
      }
      config.Locations.NoDispatchZones[editingIndex] = draft;
      config = { ...config };
      advanced = JSON.stringify(config, null, 2);
      zoneDraft = null;
      editingIndex = -1;
      status = 'Edição aplicada ao rascunho. Clique em Salvar e publicar.';
      statusType = 'success';
    } catch (error) {
      status = error instanceof Error ? error.message : 'Dados inválidos.';
      statusType = 'error';
    }
  }

  function applyAdvanced() {
    try {
      config = JSON.parse(advanced);
      ensureShape();
      status = 'JSON aplicado localmente. Clique em Salvar para publicar.';
      statusType = 'success';
    } catch (error) {
      status = 'JSON inválido. Revise vírgulas, chaves e valores.';
      statusType = 'error';
    }
  }

  async function save() {
    saving = true;
    status = '';
    const response: any = await SendNUI('saveDispatchAdminConfig', config);
    saving = false;
    if (response?.ok) {
      ADMIN_PAYLOAD.set(response);
      config = clone(response.config);
      ensureShape();
      advanced = JSON.stringify(config, null, 2);
      status = 'Configuração publicada para todos os jogadores.';
      statusType = 'success';
    } else {
      status = response?.error || 'Não foi possível salvar.';
      statusType = 'error';
    }
  }
</script>

{#if $ADMIN_OPEN && config}
  <div class="pd-modal-overlay pd-admin-overlay" on:click|self={() => ADMIN_OPEN.set(false)} transition:fade={{ duration: 120 }}>
    <section class="pd-admin" in:scale={{ start: .97, duration: 160 }}>
      <header class="pd-admin-head">
        <div class="pd-brand-mark"><i class="fas fa-tower-broadcast"></i></div>
        <div>
          <span class="pd-admin-eyebrow">FORGEBOX · CENTRAL DE OPERAÇÕES</span>
          <h2>Configuração do Dispatch</h2>
        </div>
        <span class="pd-live"><i></i> Sincronizado</span>
        <button class="pd-ctl" on:click={() => ADMIN_OPEN.set(false)}><i class="fas fa-xmark"></i></button>
      </header>

      <nav class="pd-admin-tabs">
        <button class:active={tab === 'general'} on:click={() => tab = 'general'}><i class="fas fa-sliders"></i> Geral</button>
        <button class:active={tab === 'zones'} on:click={() => tab = 'zones'}><i class="fas fa-draw-polygon"></i> Áreas ignoradas</button>
        <button class:active={tab === 'advanced'} on:click={() => tab = 'advanced'}><i class="fas fa-code"></i> Avançado</button>
      </nav>

      <div class="pd-admin-body pd-scroll">
        {#if tab === 'general'}
          <div class="pd-admin-grid">
            <label><span>Duração do alerta</span><small>Segundos na tela</small><input type="number" min="1" max="120" value={config.AlertTime} on:input={(e) => numeric('AlertTime', e.currentTarget.value)} /></label>
            <label><span>Chamados no histórico</span><small>Máximo exibido</small><input type="number" min="1" max="250" value={config.MaxCallList} on:input={(e) => numeric('MaxCallList', e.currentTarget.value)} /></label>
            <label><span>Alertas simultâneos</span><small>Pilhas na interface</small><input type="number" min="1" max="20" value={config.MaxVisibleAlerts} on:input={(e) => numeric('MaxVisibleAlerts', e.currentTarget.value)} /></label>
            <label><span>Expiração do chamado</span><small>Minutos; zero desativa</small><input type="number" min="0" max="1440" value={config.CallLifetime} on:input={(e) => numeric('CallLifetime', e.currentTarget.value)} /></label>
          </div>
          <section class="pd-jobs">
            <div class="pd-jobs-head">
              <div><b>Empregos autorizados</b><span>Selecione quem pode receber e acessar os chamados</span></div>
              <em>{config.Jobs?.length || 0} selecionados</em>
            </div>
            <div class="pd-jobs-grid pd-scroll">
              {#each jobOptions as job (job.name)}
                <label class:checked={config.Jobs?.includes(job.name)}>
                  <input type="checkbox" checked={config.Jobs?.includes(job.name)} on:change={() => toggleJob(job.name)} />
                  <i class="fas fa-briefcase"></i>
                  <div><b>{job.label}</b><span>{job.name}{job.type ? ` · ${job.type}` : ''}</span></div>
                  <i class="fas fa-check check"></i>
                </label>
              {:else}
                <div class="pd-empty pd-jobs-empty"><b>Nenhum emprego cadastrado</b><span>O PR Bridge não retornou empregos da framework.</span></div>
              {/each}
            </div>
          </section>
          <div class="pd-admin-cards">
            <button class="pd-choice" class:on={config.FilteredBroadcast === true} on:click={() => config.FilteredBroadcast = !config.FilteredBroadcast}><i class="fas fa-satellite-dish"></i><div><b>Filtro no servidor</b><span>Envia somente aos empregos elegíveis</span></div><em>{config.FilteredBroadcast ? 'ATIVO' : 'INATIVO'}</em></button>
            <button class="pd-choice" class:on={config.FilterOnDuty === true} on:click={() => config.FilterOnDuty = !config.FilterOnDuty}><i class="fas fa-user-shield"></i><div><b>Somente em serviço</b><span>Ignora agentes fora de serviço</span></div><em>{config.FilterOnDuty ? 'ATIVO' : 'INATIVO'}</em></button>
            <button class="pd-choice" class:on={config.PhoneRequired === true} on:click={() => config.PhoneRequired = !config.PhoneRequired}><i class="fas fa-mobile-screen"></i><div><b>Telefone obrigatório</b><span>Exige telefone para 190/911</span></div><em>{config.PhoneRequired ? 'ATIVO' : 'INATIVO'}</em></button>
          </div>
        {:else if tab === 'zones'}
          <div class="pd-zone-intro">
            <div><h3>Áreas sem despacho</h3><p>Dentro destas áreas, alertas automáticos são ignorados. Polígonos usam o mesmo editor 3D das Safe Zones.</p></div>
            <span>{config.Locations.NoDispatchZones.length} próprias · {$ADMIN_PAYLOAD.externalZones?.length || 0} vinculadas</span>
          </div>
          <div class="pd-safe-link">
            <div class="pd-safe-icon"><i class="fas fa-shield-halved"></i></div>
            <div><b>Usar Safe Zones do Forge Small Resources</b><span>Sincroniza polígonos e círculos ativos como áreas sem alertas. A integração é opcional.</span></div>
            <button class="pd-toggle" class:pd-toggle--on={config.SafeZoneIntegration.Enabled === true} on:click={() => config.SafeZoneIntegration.Enabled = !config.SafeZoneIntegration.Enabled}></button>
          </div>
          <div class="pd-zone-create">
            <input bind:value={zoneName} maxlength="64" placeholder="Nome da área" />
            <button class="pd-btn" disabled={!!pendingShape} on:click={() => createZone('sphere')}><i class="fas fa-circle-dot"></i> Novo círculo</button>
            <button class="pd-btn pd-btn--primary" disabled={!!pendingShape} on:click={() => createZone('poly')}><i class="fas fa-draw-polygon"></i> Novo polígono</button>
          </div>
          <div class="pd-zone-list">
            {#each config.Locations.NoDispatchZones as zone, index}
              <article>
                <div class="pd-zone-shape"><i class="fas fa-{zone.shape === 'poly' ? 'draw-polygon' : zone.shape === 'sphere' ? 'circle-dot' : 'vector-square'}"></i></div>
                <div><b>{zone.label || zone.name}</b><span>{zone.shape || 'box'} · {zone.shape === 'poly' ? `${zone.points?.length || 0} pontos` : zone.shape === 'sphere' ? `${zone.radius || 0} m` : `${zone.length || 0} × ${zone.width || 0} m`}</span></div>
                <div class="pd-zone-actions">
                  <button class="pd-ctl" title="Teleportar para a área publicada" aria-label="Teleportar para a área" on:click={() => teleportZone(zone, index)}><i class="fas fa-location-crosshairs"></i></button>
                  <button class="pd-ctl" title="Editar dados e geometria" aria-label="Editar área" disabled={!!pendingShape} on:click={() => editZone(zone, index)}><i class="fas fa-pen"></i></button>
                  <button class="pd-ctl" class:pd-zone-debug-on={debugVisible(zone, index)} title="Debug individual, somente para você" aria-label="Alternar depuração da área" aria-pressed={debugVisible(zone, index)} disabled={debugBusy || zone.active === false} on:click={() => toggleDebug(zone, index)}><i class="fas fa-bug"></i></button>
                  <button class="pd-toggle pd-toggle--sm" title="Ativar ou desativar área" aria-label="Ativar ou desativar área" class:pd-toggle--on={zone.active !== false} on:click={() => { zone.active = zone.active === false; config = {...config}; }}></button>
                  <button class="pd-icon-danger" title="Excluir área" aria-label="Excluir área" disabled={!!pendingShape} on:click={() => removeZone(index)}><i class="fas fa-trash"></i></button>
                </div>
              </article>
            {:else}
              <div class="pd-empty"><i class="fas fa-location-crosshairs"></i><b>Nenhuma área própria</b><span>Crie um círculo ou polígono diretamente no mundo.</span></div>
            {/each}
          </div>
          {#if zoneDraft}
            <section class="pd-zone-editor">
              <h3>Editar área · {zoneDraft.shape}</h3>
              <div class="pd-admin-grid">
                <label class="wide"><span>Nome</span><input bind:value={zoneDraft.label} maxlength="64" /></label>
                {#if zoneDraft.shape !== 'poly'}
                  {#each ['x', 'y', 'z'] as axis}
                    <label><span>Coordenada {axis.toUpperCase()}</span><input type="number" step="0.01" bind:value={zoneDraft.coords[axis]} /></label>
                  {/each}
                {/if}
                {#if zoneDraft.shape === 'sphere'}
                  <label><span>Raio (m)</span><input type="number" min="0.5" max="2000" step="0.1" bind:value={zoneDraft.radius} /></label>
                {:else if zoneDraft.shape === 'box'}
                  <label><span>Comprimento (m)</span><input type="number" min="0.5" max="2000" step="0.1" bind:value={zoneDraft.length} /></label>
                  <label><span>Largura (m)</span><input type="number" min="0.5" max="2000" step="0.1" bind:value={zoneDraft.width} /></label>
                  <label><span>Altura (m)</span><input type="number" min="0.5" max="1000" step="0.1" bind:value={zoneDraft.height} /></label>
                  <label><span>Direção (graus)</span><input type="number" step="0.1" bind:value={zoneDraft.heading} /></label>
                {:else}
                  <label><span>Altura (m)</span><input type="number" min="0.5" max="1000" step="0.1" bind:value={zoneDraft.thickness} /></label>
                {/if}
              </div>
              {#if zoneDraft.shape === 'poly'}
                <label class="pd-zone-points">Pontos do polígono (JSON: x, y, z)<textarea bind:value={geometryText} spellcheck="false"></textarea></label>
              {/if}
              <div class="pd-zone-editor-actions">
                {#if zoneDraft.shape !== 'box'}
                  <button class="pd-btn" disabled={!!pendingShape} on:click={() => createZone(zoneDraft.shape, true)}><i class="fas fa-draw-polygon"></i> Redesenhar no mundo</button>
                {/if}
                <button class="pd-btn" disabled={!!pendingShape} on:click={() => { zoneDraft = null; editingIndex = -1; }}>Cancelar edição</button>
                <button class="pd-btn pd-btn--primary" disabled={!!pendingShape} on:click={applyZoneEdit}>Aplicar edição</button>
              </div>
            </section>
          {/if}
          {#if $ADMIN_PAYLOAD.externalZones?.length}
            <p class="pd-zone-linked-note">Áreas vinculadas: a geometria pertence ao Forge Smallresources. Edite pelo gerenciador de Safe Zones para manter a sincronização.</p>
            <div class="pd-zone-list">
              {#each $ADMIN_PAYLOAD.externalZones as zone, index}
                <article>
                  <div class="pd-zone-shape"><i class="fas fa-link"></i></div>
                  <div><b>{zone.label || zone.name}</b><span>Vinculada · {zone.shape}</span></div>
                  <button class="pd-ctl" title="Teleportar para a área vinculada" aria-label="Teleportar para a área vinculada" on:click={() => teleportZone(zone, index)}><i class="fas fa-location-crosshairs"></i></button>
                </article>
              {/each}
            </div>
          {/if}
        {:else}
          <div class="pd-code-head"><div><h3>Configuração completa</h3><p>Blips, cores, sons, scanner e demais opções avançadas.</p></div><button class="pd-btn" on:click={applyAdvanced}><i class="fas fa-check"></i> Aplicar JSON</button></div>
          <textarea class="pd-json" bind:value={advanced} spellcheck="false"></textarea>
        {/if}
      </div>

      <footer class="pd-admin-foot">
        <span class:success={statusType === 'success'} class:error={statusType === 'error'}>{status}</span>
        <button class="pd-btn" on:click={() => ADMIN_OPEN.set(false)}>Fechar</button>
        <button class="pd-btn pd-btn--primary" disabled={saving || !!zoneDraft || !!pendingShape} on:click={save}><i class="fas fa-cloud-arrow-up"></i> {saving ? 'Salvando…' : 'Salvar e publicar'}</button>
      </footer>
    </section>
  </div>
{/if}
