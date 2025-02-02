package com.unicorn.store.webui;

import com.unicorn.store.model.Unicorn;
import com.unicorn.store.service.UnicornService;
import org.primefaces.PrimeFaces;

import javax.annotation.PostConstruct;
import javax.faces.application.FacesMessage;
import javax.faces.context.FacesContext;
import javax.faces.view.ViewScoped;
import javax.inject.Inject;
import javax.inject.Named;
import java.io.Serializable;
import java.util.List;

@Named
@ViewScoped
public class UnicornPresenter implements Serializable {
    @Inject
    UnicornService unicornService;

    private List<Unicorn> unicorns;
    private Unicorn selectedUnicorn;

    public List<Unicorn> getUnicorns() {
        return unicorns;
    }

    public Unicorn getSelectedUnicorn() {
        return selectedUnicorn;
    }

    public void setSelectedUnicorn(Unicorn selectedUnicorn) {
        this.selectedUnicorn = selectedUnicorn;
    }

    @PostConstruct
    void init() {
        this.unicorns = unicornService.getAllUnicorns();
    }

    public void openNew() {
        this.selectedUnicorn = new Unicorn();
    }

    public void saveUnicorn() {
    if (this.selectedUnicorn.getId() == null) {
        this.unicornService.createUnicorn(this.selectedUnicorn);
        this.unicorns.add(this.selectedUnicorn);
        FacesContext.getCurrentInstance().addMessage(null, new FacesMessage("Unicorn added"));
    } else {
        this.unicornService.updateUnicorn(this.selectedUnicorn, this.selectedUnicorn.getId());
        FacesContext.getCurrentInstance().addMessage(null, new FacesMessage("Unicorn updated"));
    }
        PrimeFaces.current().executeScript("PF('manageUnicornDialog').hide()");
        PrimeFaces.current().ajax().update("form:messages", "form:dt-unicorns");
    }

        public void deleteUnicorn() {
        this.unicornService.deleteUnicorn(this.selectedUnicorn.getId());
        this.unicorns.remove(this.selectedUnicorn);
        this.selectedUnicorn = null;
        FacesContext.getCurrentInstance().addMessage(null, new FacesMessage("Unicorn removed"));
        PrimeFaces.current().ajax().update("form:messages", "form:dt-unicorns");
    }
}
