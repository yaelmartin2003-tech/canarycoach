let userRole = 'ADMIN'; 

document.addEventListener('DOMContentLoaded', () => {
    checkPermissions();
});

function checkPermissions() {
    const navAdmin = document.getElementById('nav-admin');
    const adminInd = document.getElementById('admin-indicator');

    if (userRole === 'ADMIN') {
        navAdmin.classList.remove('hidden');
        adminInd.classList.remove('hidden');
    } else {
        navAdmin.classList.add('hidden');
        adminInd.classList.add('hidden');
    }
}

function showSection(sectionId, element) {
    // Ocultar todas las secciones
    document.querySelectorAll('main section').forEach(section => {
        section.classList.add('hidden');
    });

    // Mostrar la elegida
    document.getElementById(`view-${sectionId}`).classList.remove('hidden');

    // Quitar "active" de todas las pestañas
    document.querySelectorAll('.nav-item').forEach(item => {
        item.classList.remove('active');
    });
    // Poner "active" a la clicada
    element.classList.add('active');
}

function toggleAdminMode() {
    userRole = (userRole === 'ADMIN') ? 'USER' : 'ADMIN';
    checkPermissions();
    alert("Cambiado a: " + userRole);
    // Recargar vista inicio por seguridad
    location.reload(); 
}

// Tabs navegación horizontal
document.querySelectorAll('.nav-tab').forEach(tab => {
  tab.addEventListener('click', function() {
    const tabName = this.dataset.tab;
    
    // Activar tab
    document.querySelectorAll('.nav-tab').forEach(t => t.classList.remove('activo'));
    document.querySelectorAll('.tab-contenido').forEach(t => t.classList.remove('activo'));
    this.classList.add('activo');
    document.querySelector(`[data-tab="${tabName}"]`).classList.add('activo');
    
    // Mover indicador
    const tabs = document.querySelector('.barra-nav-horizontal');
    const indicador = tabs.querySelector('.indicador');
    const rect = this.getBoundingClientRect();
    const tabsRect = tabs.getBoundingClientRect();
    indicador.style.left = (rect.left - tabsRect.left) + 'px';
    indicador.style.width = rect.width + 'px';
  });
});

// Cargar nombre del perfil
function cargarNombreUsuario() {
  const nombre = localStorage.getItem('perfil_nombre') || 'Usuario';
  document.getElementById('nombreUsuario').textContent = nombre;
}
cargarNombreUsuario();

// Estilos CSS para tabs activos
const style = document.createElement('style');
style.textContent = `
  .nav-tab.activo { color: var(--azul-activo) !important; }
  .tab-contenido.activo { display: block; }
  .tab-contenido { display: none; }
  .barra-dia { cursor: pointer; text-align: center; flex: 1; }
  .barra-dia span { font-weight: 600; margin-bottom: 0.5rem; display: block; }
  .barra { width: 24px; height: 0; border-radius: 4px; transition: height 0.3s; margin: 0 auto; }
`;
document.head.appendChild(style);

// Barra inferior con franja móvil (NUEVA FUNCIÓN)
function mostrarVista(id, btn) {
  // Ocultar todas las vistas principales
  document.querySelectorAll('.vista').forEach(v => v.classList.remove('activa'));
  document.getElementById(id).classList.add('activa');

  // Activar botón inferior
  document.querySelectorAll('nav button').forEach(b => b.classList.remove('activo'));
  btn.classList.add('activo');
  
  // Scroll suave
  document.getElementById(id).scrollIntoView({ 
    behavior: 'smooth', 
    block: 'start' 
  });
}