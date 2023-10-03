package com.unicorn.store.webui;

import com.unicorn.store.model.Unicorn;
import com.unicorn.store.data.UnicornRepository;
import org.primefaces.PrimeFaces;

import javax.annotation.PostConstruct;
import javax.faces.application.FacesMessage;
import javax.faces.context.FacesContext;
import javax.faces.view.ViewScoped;
import javax.inject.Inject;
import javax.inject.Named;
import javax.transaction.Transactional;
import java.io.Serializable;
import java.util.List;

@Named
@ViewScoped
public class UnicornPresenter implements Serializable {

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

  @Inject
  UnicornRepository unicornRepository;

  @PostConstruct
  void init() {
    this.unicorns = unicornRepository.findAll();
  }

  public void openNew() {
    this.selectedUnicorn = new Unicorn();
  }

  @Transactional
  public void saveUnicorn() {
    if (this.selectedUnicorn.getId() == null) {
      this.unicornRepository.persist(this.selectedUnicorn);
      this.unicorns.add(this.selectedUnicorn);
      FacesContext.getCurrentInstance().addMessage(null, new FacesMessage("Unicorn added"));
    } else {
      this.unicornRepository.merge(this.selectedUnicorn);
      FacesContext.getCurrentInstance().addMessage(null, new FacesMessage("Unicorn updated"));
    }

    PrimeFaces.current().executeScript("PF('manageUnicornDialog').hide()");
    PrimeFaces.current().ajax().update("form:messages", "form:dt-unicorns");
  }

  @Transactional
  public void deleteUnicorn() {
    this.unicornRepository.removeById(this.selectedUnicorn.getId());
    this.unicorns.remove(this.selectedUnicorn);
    this.selectedUnicorn = null;
    FacesContext.getCurrentInstance().addMessage(null, new FacesMessage("Unicorn removed"));
    PrimeFaces.current().ajax().update("form:messages", "form:dt-unicorns");
  }

}
